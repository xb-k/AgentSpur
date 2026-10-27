import AppKit
import CoreServices
import Foundation
import UserNotifications

@main
final class AgentSpurApp: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    // 强引用持有 AppDelegate，防止 swift build -c release (-O) 下 NSApplication.weak delegate 被提前释放
    private static var sharedDelegate: AgentSpurApp?

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let popoverVC = StatusPopoverViewController()
    private let dbReader = OpenCodeDBReader()

    // 所有 SQLite 读取与 AppleScript/tmux 真实终端探测全部放在后台串行队列，主线程 0 阻塞！
    private let workerQueue = DispatchQueue(label: "com.agentspur.worker", qos: .utility)
    private var debounceWorkItem: DispatchWorkItem?
    private var isReloadingInBackground = false

    private var animTimer: Timer?
    private var fsEventStream: FSEventStreamRef?
    private var globalMouseMonitor: Any?
    private var isShowingModalPanel: Bool = false
    private var frameIndex: Int = 0
    private var tickCounter: Int = 0

    private var latestSnapshot: OpenCodeDBSnapshot
    private var cachedRealWindows: [RealTerminalWindow] = []

    private var customPacks: [DeepSeekRolePack] = []
    private var activePackId: String = "pack-gin-droplet"
    private var currencyMode: CurrencyDisplayMode = .cny
    private var csvReconciliation: OfficialCSVReconciliation?
    private var silentAlertEnabled: Bool = true
    private var autoFocusEnabled: Bool = true
    private var selectedRealWindowId: String? = nil // nil 表示自动跟随当前前台活跃终端

    private var quota = QuotaSnapshot(
        apiTotalBalance: nil,
        apiCurrency: "CNY",
        walletBreakdownLabel: "Paid",
        usdToCnyRate: 7.12,
        fxSourceLabel: "初始化中",
        resetTimeLabel: "04:00重置",
        lastRefreshedHHMM: TimeFormatters.currentHHMM()
    )

    private let defaults = UserDefaults.standard

    private var canUseUserNotifications: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    override init() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let defaultTier = DeepSeekPricingEngine.classifyModel("deepseek-flash")
        self.latestSnapshot = OpenCodeDBSnapshot(
            masters: [],
            urgentSubTask: nil,
            topState: .completed,
            topStateEnteredAtMs: nowMs,
            todayHourlySeries: (0..<24).map {
                TodayHourlyPoint(
                    hour: $0,
                    hourLabel: String(format: "%02d", $0),
                    requestCount: 0,
                    costCny: 0.0,
                    cacheHitPercent: 0.0,
                    isPeakHour: false,
                    isCurrentHour: false
                )
            },
            billing: BillingTelemetrySummary.empty(
                dateLabel: TimeFormatters.todayShortLabel(),
                tier: defaultTier
            ),
            realWindows: [],
            activeDbFileName: "opencode.db",
            dbExists: false
        )
        super.init()
    }

    static func main() {
        // 支持在打包 DMG 时直接调用二进制渲染高清 1024x1024 AppIcon PNG
        let args = CommandLine.arguments
        if let flagIdx = args.firstIndex(of: "--export-icon"), flagIdx + 1 < args.count {
            let outputPath = args[flagIdx + 1]
            let ok = SpriteRenderer.exportHighResAppIconPNG(to: outputPath, pixelSize: 1024)
            exit(ok ? 0 : 1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // 纯菜单栏轻量应用，无 Dock 图标
        let delegate = AgentSpurApp()
        sharedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadPreferences()
        if canUseUserNotifications {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.target = self
            btn.action = #selector(togglePopover(_:))
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = popoverVC
        popover.delegate = self

        // 监听应用失焦与前台应用切换，确保切换到其他窗口（点击桌面/终端/⌘Tab）时自动收起菜单卡片
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceDidActivateApp(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        wirePopoverCallbacks()
        updateMenuBarStatusTextAndTooltip()
        start15FPSRunLoop()
        startFSEventsReadOnlyWatcher()
        refreshExchangeRateAndQuota(refreshTerminals: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeOutsideClickMonitor()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private var allPacks: [DeepSeekRolePack] {
        DeepSeekRolePack.builtInPacks + customPacks
    }

    private var activePack: DeepSeekRolePack {
        allPacks.first(where: { $0.id == activePackId }) ?? DeepSeekRolePack.builtInPacks[0]
    }

    // MARK: - Preferences Persistence

    private func loadPreferences() {
        if defaults.object(forKey: "silentAlertEnabled") != nil {
            silentAlertEnabled = defaults.bool(forKey: "silentAlertEnabled")
        }
        if defaults.object(forKey: "autoFocusEnabled") != nil {
            autoFocusEnabled = defaults.bool(forKey: "autoFocusEnabled")
        }
        selectedRealWindowId = defaults.string(forKey: "selectedRealWindowId")
        if let savedPackId = defaults.string(forKey: "activePackId") {
            activePackId = savedPackId
        }
        if let savedCurr = defaults.string(forKey: "currencyMode"),
           let mode = CurrencyDisplayMode(rawValue: savedCurr) {
            currencyMode = mode
        }
        let cachedRate = defaults.double(forKey: "lastKnownUsdToCnyRate")
        if cachedRate > 5.0 && cachedRate < 10.0 {
            quota.usdToCnyRate = cachedRate
            quota.fxSourceLabel = "缓存汇率"
        }
        if let data = defaults.data(forKey: "customPacksData"),
           let decoded = try? JSONDecoder().decode([DeepSeekRolePack].self, from: data) {
            customPacks = decoded
        }
        if let csvData = defaults.data(forKey: "officialCSVReconciliationData"),
           let decodedCSV = try? JSONDecoder().decode(OfficialCSVReconciliation.self, from: csvData) {
            csvReconciliation = decodedCSV
        }
    }

    private func saveCustomPacks() {
        if let data = try? JSONEncoder().encode(customPacks) {
            defaults.set(data, forKey: "customPacksData")
        }
    }

    // MARK: - Popover Actions Wiring

    private func wirePopoverCallbacks() {
        popoverVC.onRefreshQuota = { [weak self] in
            self?.refreshExchangeRateAndQuota(refreshTerminals: true)
        }
        popoverVC.onToggleCurrencyMode = { [weak self] in
            guard let self else { return }
            self.currencyMode = self.currencyMode.next
            self.defaults.set(self.currencyMode.rawValue, forKey: "currencyMode")
            self.updateMenuBarStatusTextAndTooltip()
            self.renderFullPopoverIfShown()
        }
        popoverVC.onImportOfficialCSVs = { [weak self] parsed in
            guard let self else { return }
            self.csvReconciliation = parsed
            if let data = try? JSONEncoder().encode(parsed) {
                self.defaults.set(data, forKey: "officialCSVReconciliationData")
            }
            self.updateMenuBarStatusTextAndTooltip()
            self.renderFullPopoverIfShown()
        }
        popoverVC.onClearOfficialCSV = { [weak self] in
            guard let self else { return }
            self.csvReconciliation = nil
            self.defaults.removeObject(forKey: "officialCSVReconciliationData")
            self.updateMenuBarStatusTextAndTooltip()
            self.renderFullPopoverIfShown()
        }
        popoverVC.onToggleSilentAlert = { [weak self] enabled in
            guard let self else { return }
            self.silentAlertEnabled = enabled
            self.defaults.set(enabled, forKey: "silentAlertEnabled")
        }
        popoverVC.onToggleAutoFocus = { [weak self] enabled in
            guard let self else { return }
            self.autoFocusEnabled = enabled
            self.defaults.set(enabled, forKey: "autoFocusEnabled")
            if enabled {
                self.scheduleBackgroundReload(refreshTerminals: true, immediate: true)
            } else {
                self.renderFullPopoverIfShown()
            }
        }
        popoverVC.onSelectRealWindowId = { [weak self] winId in
            guard let self else { return }
            self.selectedRealWindowId = winId
            if let winId {
                self.defaults.set(winId, forKey: "selectedRealWindowId")
            } else {
                self.defaults.removeObject(forKey: "selectedRealWindowId")
            }
            self.renderFullPopoverIfShown()
        }
        popoverVC.onSelectPack = { [weak self] selectedName in
            guard let self,
                  let found = self.allPacks.first(where: { $0.name == selectedName }) else { return }
            self.activePackId = found.id
            self.defaults.set(found.id, forKey: "activePackId")
            self.renderFullPopoverIfShown()
        }
        popoverVC.onImportCustomPack = { [weak self] pack in
            guard let self else { return }
            self.customPacks.removeAll(where: { $0.id == pack.id })
            self.customPacks.append(pack)
            self.activePackId = pack.id
            self.defaults.set(pack.id, forKey: "activePackId")
            self.saveCustomPacks()
            self.renderFullPopoverIfShown()
        }
        popoverVC.onConfigureApiKey = { [weak self] in
            self?.promptForDeepSeekApiKey()
        }
        popoverVC.onFilterChanged = { [weak self] in
            self?.renderFullPopoverIfShown()
        }
        popoverVC.onRequestClosePopover = { [weak self] in
            self?.closePopover(nil)
        }
        popoverVC.onModalPanelStateChange = { [weak self] showing in
            self?.isShowingModalPanel = showing
        }
        popoverVC.onQuitApp = {
            NSApplication.shared.terminate(nil)
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let btn = statusItem.button else { return }
        if popover.isShown {
            closePopover(sender)
        } else {
            openPopover(relativeTo: btn)
        }
    }

    private func openPopover(relativeTo button: NSStatusBarButton) {
        // 先展示 _NSPopoverWindow 再调用 activate()，确保 macOS 14/15 WindowServer 将纯菜单栏 (.accessory) 应用设为活跃 Key Window
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApplication.shared.activate()
        popoverVC.view.window?.makeKey()
        installOutsideClickMonitor()
        renderFullPopoverIfShown()
        // 展开时在后台异步刷新一次真实终端标签页与今日数据库快照，绝不阻塞弹窗动画
        scheduleBackgroundReload(refreshTerminals: true, immediate: true)
    }

    private func closePopover(_ sender: Any?) {
        removeOutsideClickMonitor()
        if popover.isShown {
            popover.performClose(sender)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitor()
    }

    @objc private func handleAppDidResignActive(_ notification: Notification) {
        guard popover.isShown, !isShowingModalPanel, NSApplication.shared.modalWindow == nil else { return }
        closePopover(nil)
    }

    @objc private func handleWorkspaceDidActivateApp(_ notification: Notification) {
        guard popover.isShown, !isShowingModalPanel, NSApplication.shared.modalWindow == nil else { return }
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            closePopover(nil)
        }
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            guard !self.isShowingModalPanel, NSApplication.shared.modalWindow == nil else { return }

            let mouseScreenPt = NSEvent.mouseLocation
            // 点击在状态栏图标自身区域时交给 statusItem.button 的 togglePopover 处理，避免按下关闭、抬起又重开
            if let btnWin = self.statusItem?.button?.window,
               btnWin.frame.insetBy(dx: -4, dy: -4).contains(mouseScreenPt) {
                return
            }
            if let popWin = self.popoverVC.view.window,
               popWin.frame.contains(mouseScreenPt) {
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.closePopover(nil)
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }

    // MARK: - Zero-Lag 15 FPS Sprite Loop + 1 Hz Timer Loop

    private func start15FPSRunLoop() {
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            guard let self, let btn = self.statusItem.button else { return }
            self.frameIndex = (self.frameIndex + 1) % 15
            self.tickCounter += 1

            let state = self.latestSnapshot.topState
            btn.image = SpriteRenderer.renderSpriteFrame(
                state: state,
                pack: self.activePack,
                frame: self.frameIndex,
                pointSize: 18
            )
            btn.imagePosition = .imageLeading

            // 浮层展开时，15 FPS 仅原地替换 NSImage 帧，不重建任何视图！
            if self.popover.isShown {
                self.popoverVC.tickAnimationFrame(
                    topState: state,
                    activePack: self.activePack,
                    frameIndex: self.frameIndex
                )
            }

            // 每 1 秒（15 帧）轻量更新一次秒表文字与 Tooltip
            if self.tickCounter % 15 == 0 {
                self.updateMenuBarStatusTextAndTooltip()
                if self.popover.isShown {
                    self.popoverVC.tickOneSecondTimers(
                        topState: state,
                        topEnteredAtMs: self.latestSnapshot.topStateEnteredAtMs
                    )
                }
            }

            // 每 4 秒在后台静默同步一次（兜底某些 WAL 写入未触发文件级事件，以及刷新真实前台终端高亮）
            if self.tickCounter % 60 == 0 {
                let needTermRefresh = self.popover.isShown
                self.scheduleBackgroundReload(refreshTerminals: needTermRefresh, immediate: true)
            }

            // 每 30 分钟自动更新一次线上汇率
            if self.tickCounter % (15 * 1800) == 0 {
                self.refreshExchangeRateOnly()
            }
        }
        if let animTimer {
            RunLoop.main.add(animTimer, forMode: .common)
        }
    }

    private func updateMenuBarStatusTextAndTooltip() {
        guard let btn = statusItem?.button else { return }
        let state = latestSnapshot.topState
        let safeRate = max(1.0, quota.usdToCnyRate)
        let windowBadge = DeepSeekPricingEngine.priceWindow().badgeText

        let menuMoneyStr: String
        if let apiBal = quota.apiTotalBalance {
            let balCny = quota.apiCurrency == "USD" ? apiBal * safeRate : apiBal
            menuMoneyStr = DeepSeekPricingEngine.formatMoney(
                amountCny: balCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: false
            )
        } else if let csv = csvReconciliation {
            let cny = csv.currency == "USD" ? csv.totalCostInOriginalCurrency * safeRate : csv.totalCostInOriginalCurrency
            menuMoneyStr = DeepSeekPricingEngine.formatMoney(
                amountCny: cny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: true
            )
        } else {
            menuMoneyStr = DeepSeekPricingEngine.formatMoney(
                amountCny: latestSnapshot.billing.spurCostCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: true
            )
        }

        let titleStr = " \(state.label) · \(menuMoneyStr) · \(windowBadge)"
        btn.attributedTitle = NSAttributedString(
            string: titleStr,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            ]
        )

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let b = latestSnapshot.billing
        let fxInfo = String(
            format: "今日精算 ¥%.4f · Cache命中 %.1f%% (已省 ¥%.2f) · 汇率 $1=¥%.4f",
            b.spurCostCny,
            b.cacheHitRatePercent,
            b.cacheSavedCny,
            safeRate
        )
        if let urgent = latestSnapshot.urgentSubTask {
            let timerStr = TimeFormatters.liveStateTimerLabel(
                state: urgent.state,
                enteredAtMs: urgent.stateEnteredAtMs,
                nowMs: nowMs
            )
            let consoleName = urgent.matchedWindow?.popupMenuTitle ?? urgent.consoleBadgeText
            btn.toolTip = "AgentSpur 当前任务：\(urgent.title)\n控制台：\(consoleName) · \(timerStr)\n\(fxInfo)"
        } else {
            btn.toolTip = "AgentSpur · \(latestSnapshot.activeDbFileName) 今日实时只读监控\n\(fxInfo)"
        }
    }

    private func renderFullPopoverIfShown() {
        guard popover.isShown else { return }
        popoverVC.renderSnapshot(
            snapshot: latestSnapshot,
            quota: quota,
            currencyMode: currencyMode,
            csvReconciliation: csvReconciliation,
            activePack: activePack,
            allPacks: allPacks,
            frameIndex: frameIndex,
            autoFocusEnabled: autoFocusEnabled,
            selectedWindowId: selectedRealWindowId,
            silentAlertEnabled: silentAlertEnabled
        )
    }

    // MARK: - Background Debounced SQLite & Real Console Reload (Zero Main-Thread Blocking)

    private func scheduleBackgroundReload(refreshTerminals: Bool, immediate: Bool = false) {
        debounceWorkItem?.cancel()
        let delay: TimeInterval = immediate ? 0.02 : 0.45

        let rateCopy = quota.usdToCnyRate
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.workerQueue.async { [weak self] in
                guard let self, !self.isReloadingInBackground else { return }
                self.isReloadingInBackground = true
                defer { self.isReloadingInBackground = false }

                let windows: [RealTerminalWindow]
                if refreshTerminals || self.cachedRealWindows.isEmpty {
                    windows = TerminalBridge.discoverRealWindows()
                    self.cachedRealWindows = windows
                } else {
                    windows = self.cachedRealWindows
                }

                var completedTitles: [String] = []
                let snap = self.dbReader.readSnapshot(
                    usdToCnyRate: rateCopy,
                    realWindows: windows
                ) { title in
                    completedTitles.append(title)
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let changed = (snap != self.latestSnapshot)
                    self.latestSnapshot = snap
                    for t in completedTitles {
                        self.postSilentCompletionNotification(taskTitle: t)
                    }
                    if changed {
                        self.updateMenuBarStatusTextAndTooltip()
                        self.renderFullPopoverIfShown()
                    }
                }
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startFSEventsReadOnlyWatcher() {
        let dirPath = dbReader.opencodeDirPath
        if !FileManager.default.fileExists(atPath: dirPath) {
            try? FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [dirPath] as CFArray
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let app = Unmanaged<AgentSpurApp>.fromOpaque(info).takeUnretainedValue()
            app.scheduleBackgroundReload(refreshTerminals: false, immediate: false)
        }

        if let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.50,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) {
            fsEventStream = stream
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    // MARK: - Online Exchange Rate + DeepSeek Quota Refresh (`⌘R`)

    private func refreshExchangeRateOnly() {
        DeepSeekPricingEngine.fetchLiveUsdToCnyRate { [weak self] rate, source in
            guard let self else { return }
            self.quota.usdToCnyRate = rate
            self.quota.fxSourceLabel = source
            self.defaults.set(rate, forKey: "lastKnownUsdToCnyRate")
            self.scheduleBackgroundReload(refreshTerminals: false, immediate: true)
        }
    }

    private func refreshExchangeRateAndQuota(refreshTerminals: Bool) {
        quota.lastRefreshedHHMM = TimeFormatters.currentHHMM()
        refreshExchangeRateOnly()
        scheduleBackgroundReload(refreshTerminals: refreshTerminals, immediate: true)

        let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]
        let savedKey = defaults.string(forKey: "deepseekApiKey")
        let effectiveKey = (savedKey?.isEmpty == false ? savedKey : envKey) ?? ""

        if !effectiveKey.isEmpty, let url = URL(string: "https://api.deepseek.com/user/balance") {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(effectiveKey)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 6

            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                guard let self else { return }
                if let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let infos = json["balance_infos"] as? [[String: Any]],
                   let first = infos.first,
                   let totalStr = first["total_balance"] as? String,
                   let totalVal = Double(totalStr) {
                    let curr = ((first["currency"] as? String) ?? "CNY").uppercased()
                    let paidStr = (first["topped_up_balance"] as? String) ?? totalStr
                    let grantedStr = (first["granted_balance"] as? String) ?? "0.00"
                    let walletLabel = (Double(grantedStr) ?? 0) > 0
                        ? "Paid \(paidStr) · Granted \(grantedStr)"
                        : "Paid"
                    DispatchQueue.main.async {
                        self.quota.apiTotalBalance = totalVal
                        self.quota.apiCurrency = curr
                        self.quota.walletBreakdownLabel = walletLabel
                        self.updateMenuBarStatusTextAndTooltip()
                        self.renderFullPopoverIfShown()
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.quota.apiTotalBalance = nil
                    self.updateMenuBarStatusTextAndTooltip()
                    self.renderFullPopoverIfShown()
                }
            }.resume()
        } else {
            quota.apiTotalBalance = nil
            updateMenuBarStatusTextAndTooltip()
            renderFullPopoverIfShown()
        }
    }

    private func promptForDeepSeekApiKey() {
        isShowingModalPanel = true
        defer {
            isShowingModalPanel = false
            NSApplication.shared.activate()
        }

        let alert = NSAlert()
        alert.messageText = "配置 DeepSeek 余额查询 Key (可选)"
        alert.informativeText = "填入后按 ⌘R 将直连 DeepSeek 官方接口读取 Paid / Granted 钱包余额；留空则默认只展示今日 opencode.db 精算开销。"
        alert.addButton(withTitle: "保存并刷新")
        alert.addButton(withTitle: "取消")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = "sk-..."
        input.stringValue = defaults.string(forKey: "deepseekApiKey") ?? ""
        alert.accessoryView = input

        NSApplication.shared.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            let trimmed = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: "deepseekApiKey")
            refreshExchangeRateAndQuota(refreshTerminals: false)
        }
    }

    private func postSilentCompletionNotification(taskTitle: String) {
        guard silentAlertEnabled, canUseUserNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = "AgentSpur · 任务已完成"
        content.body = taskTitle
        content.sound = nil
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
