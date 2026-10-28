import AppKit
import CoreServices
import Foundation
import ServiceManagement
import UserNotifications

@main
final class AgentSpurApp: NSObject, NSApplicationDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    // 强引用持有 AppDelegate，防止 swift build -c release (-O) 下 NSApplication.weak delegate 被提前释放
    private static var sharedDelegate: AgentSpurApp?

    private var statusItem: NSStatusItem!
    private var floatingBadgePanel: FloatingStatusBadgePanel?
    private var backgroundActivityToken: NSObjectProtocol?
    private let popover = NSPopover()
    private let popoverVC = StatusPopoverViewController()
    private let dbReader = OpenCodeDBReader()

    // 所有 SQLite 读取与 AppleScript/tmux 真实终端探测全部放在后台串行队列，主线程 0 阻塞
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

    private var apiKeyProfiles: [APIKeyProfile] = []
    private var selectedKeyScopeId: String = APIKeyProfile.allKeysId

    private var customPacks: [DeepSeekRolePack] = []
    private var activePackId: String = "pack-gin-droplet"
    private var currencyMode: CurrencyDisplayMode = .cny
    private var csvReconciliation: OfficialCSVReconciliation?
    private var notificationsMuted: Bool = false // 默认开启通知与提示音
    private var autoFocusEnabled: Bool = true
    private var selectedRealWindowId: String? = nil
    private var menuBarDisplayMode: MenuBarDisplayMode = .iconOnly // 默认紧凑仅图标，减少菜单栏宽度占用
    private var floatingBadgeMode: FloatingBadgeMode = .autoWhenOccluded // 默认智能兜底：当菜单栏被刘海屏/灵动岛挂件挤压遮挡或全屏时自动浮现右上角微胶囊

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
            availableKeyScopes: [],
            effectiveProfiles: [],
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

        // 忽略 SIGHUP：即使从终端命令行直接启动，离开/关闭终端 Tab 时也绝不退出常驻进程
        signal(SIGHUP, SIG_IGN)

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // 纯菜单栏轻量应用，无 Dock 图标
        let delegate = AgentSpurApp()
        sharedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 关闭 API-Key 子面板或收起 Popover 窗口时，绝不终止菜单栏常驻进程
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 阻止 macOS App Nap 在切换到其他桌面/应用时冻结后台菜单栏图标刷新与 FSEvents 监听（不影响合盖休眠）
        backgroundActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Keep AgentSpur menu bar status item persistent and responsive across all apps and Spaces"
        )

        installStandardEditMenu()
        loadPreferences()
        if canUseUserNotifications {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }

        let initialLen = (menuBarDisplayMode == .iconOnly) ? NSStatusItem.squareLength : NSStatusItem.variableLength
        statusItem = NSStatusBar.system.statusItem(withLength: initialLen)
        statusItem.behavior = [] // 禁止被意外拖出销毁
        statusItem.autosaveName = "AgentSpurStatusItem" // 记忆用户 ⌘+拖拽 到右侧高优位置的布局
        statusItem.isVisible = true
        if let btn = statusItem.button {
            btn.target = self
            btn.action = #selector(togglePopover(_:))
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
            btn.imageScaling = .scaleProportionallyDown
            btn.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
            btn.imagePosition = (menuBarDisplayMode == .iconOnly) ? .imageOnly : .imageLeading
        }

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentSize = NSSize(width: 464, height: 556)
        popover.contentViewController = popoverVC
        popover.delegate = self

        // 监听应用失焦、前台应用切换、多桌面 Space 切换与外接显示器变化，确保菜单栏图标跨屏始终可见
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleActiveSpaceOrScreenChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceDidActivateApp(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleActiveSpaceOrScreenChanged(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        wirePopoverCallbacks()
        updateMenuBarStatusTextAndTooltip()
        syncFloatingBadgeVisibility()
        start15FPSRunLoop()
        startFSEventsReadOnlyWatcher()
        refreshExchangeRateAndQuota(refreshTerminals: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let token = backgroundActivityToken {
            ProcessInfo.processInfo.endActivity(token)
            backgroundActivityToken = nil
        }
        removeOutsideClickMonitor()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate (确保前台展开或菜单栏常驻时也能正常弹出横幅)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notificationsMuted {
            completionHandler([])
        } else {
            completionHandler([.banner, .list])
        }
    }

    private var allPacks: [DeepSeekRolePack] {
        DeepSeekRolePack.builtInPacks + customPacks
    }

    private var activePack: DeepSeekRolePack {
        allPacks.first(where: { $0.id == activePackId }) ?? DeepSeekRolePack.builtInPacks[0]
    }

    // MARK: - Preferences & Multi API-Key Persistence

    private func loadPreferences() {
        if defaults.object(forKey: "notificationsMuted") != nil {
            notificationsMuted = defaults.bool(forKey: "notificationsMuted")
        }
        if defaults.object(forKey: "autoFocusEnabled") != nil {
            autoFocusEnabled = defaults.bool(forKey: "autoFocusEnabled")
        }
        selectedRealWindowId = defaults.string(forKey: "selectedRealWindowId")
        if let savedScope = defaults.string(forKey: "selectedKeyScopeId"), !savedScope.isEmpty {
            selectedKeyScopeId = savedScope
        }
        if let savedPackId = defaults.string(forKey: "activePackId") {
            activePackId = savedPackId
        }
        if let savedCurr = defaults.string(forKey: "currencyMode"),
           let mode = CurrencyDisplayMode(rawValue: savedCurr) {
            currencyMode = mode
        }
        if let savedBarMode = defaults.string(forKey: "menuBarDisplayMode"),
           let barMode = MenuBarDisplayMode(rawValue: savedBarMode) {
            menuBarDisplayMode = barMode
        }
        if let savedBadgeMode = defaults.string(forKey: "floatingBadgeMode"),
           let bMode = FloatingBadgeMode(rawValue: savedBadgeMode) {
            floatingBadgeMode = bMode
        } else if defaults.object(forKey: "floatingBadgeEnabled") != nil {
            floatingBadgeMode = defaults.bool(forKey: "floatingBadgeEnabled") ? .always : .autoWhenOccluded
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
        if let keyData = defaults.data(forKey: "apiKeyProfilesData"),
           let decodedKeys = try? JSONDecoder().decode([APIKeyProfile].self, from: keyData) {
            apiKeyProfiles = decodedKeys
        } else if let legacyKey = defaults.string(forKey: "deepseekApiKey"), !legacyKey.isEmpty {
            apiKeyProfiles = [
                APIKeyProfile(
                    id: "key-default",
                    name: "默认主Key",
                    rawApiKey: legacyKey,
                    maskedKey: APIKeyProfile.makeMasked(legacyKey),
                    directoryKeyword: ""
                )
            ]
            saveApiKeyProfiles()
        } else {
            apiKeyProfiles = []
        }
    }

    private var effectiveApiKeyProfiles: [APIKeyProfile] {
        latestSnapshot.effectiveProfiles.isEmpty ? apiKeyProfiles : latestSnapshot.effectiveProfiles
    }

    private func saveApiKeyProfiles() {
        if let data = try? JSONEncoder().encode(apiKeyProfiles) {
            defaults.set(data, forKey: "apiKeyProfilesData")
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
        popoverVC.onSelectCurrencyMode = { [weak self] mode in
            guard let self else { return }
            self.currencyMode = mode
            self.defaults.set(mode.rawValue, forKey: "currencyMode")
            self.updateMenuBarStatusTextAndTooltip()
            self.renderFullPopoverIfShown()
        }
        popoverVC.onSelectApiKeyScope = { [weak self] scopeId in
            guard let self else { return }
            // O(1) 内存级切换 (<0.2ms)，绝不阻塞 Popover 或全表扫描 opencode.db
            self.selectedKeyScopeId = scopeId
            self.defaults.set(scopeId, forKey: "selectedKeyScopeId")
            self.updateMenuBarStatusTextAndTooltip()
            self.renderFullPopoverIfShown()
            self.refreshBalanceForActiveKeyProfile()
        }
        popoverVC.onSaveApiKeyProfile = { [weak self] name, rawSecret, directoryKeyword in
            guard let self else { return }
            self.upsertApiKeyProfile(name: name, rawSecret: rawSecret, directoryKeyword: directoryKeyword)
        }
        popoverVC.onDeleteApiKeyProfile = { [weak self] profileId in
            guard let self else { return }
            self.deleteApiKeyProfile(profileId: profileId)
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
        popoverVC.onToggleNotificationsMuted = { [weak self] in
            guard let self else { return }
            self.notificationsMuted.toggle()
            self.defaults.set(self.notificationsMuted, forKey: "notificationsMuted")
            if !self.notificationsMuted {
                // 开启提醒时立即播放一声清脆原生反馈音，确保用户感知声音链路正常
                NSSound(named: NSSound.Name("Tink"))?.play()
                if self.canUseUserNotifications {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                }
            }
            self.renderFullPopoverIfShown()
        }
        popoverVC.onTestNotificationSound = { [weak self] in
            guard let self else { return }
            if self.notificationsMuted {
                self.notificationsMuted = false
                self.defaults.set(false, forKey: "notificationsMuted")
                self.renderFullPopoverIfShown()
            }
            self.deliverAgentNotification(
                event: AgentNotificationEvent(kind: .completed, taskTitle: "通知与系统提示音自检正常"),
                forcePlay: true
            )
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
        popoverVC.onSelectPackId = { [weak self] packId in
            guard let self,
                  self.allPacks.contains(where: { $0.id == packId }) else { return }
            self.activePackId = packId
            self.defaults.set(packId, forKey: "activePackId")
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
        popoverVC.onFilterChanged = { [weak self] in
            self?.renderFullPopoverIfShown()
        }
        popoverVC.onRequestClosePopover = { [weak self] in
            self?.closePopover(nil)
        }
        popoverVC.onModalPanelStateChange = { [weak self] showing in
            guard let self else { return }
            self.isShowingModalPanel = showing
            // 保持 popover.behavior = .transient 不变（确保 _NSPopoverWindow.canBecomeKey 始终为 true，
            // 让内嵌 API-Key 输入框支持焦点与 ⌘V 粘贴），同时由 popoverShouldClose(_:) 拦截意外收起。
        }
        popoverVC.onSelectMenuBarDisplayMode = { [weak self] mode in
            guard let self else { return }
            self.menuBarDisplayMode = mode
            self.defaults.set(mode.rawValue, forKey: "menuBarDisplayMode")
            self.updateMenuBarStatusTextAndTooltip()
            self.syncFloatingBadgeVisibility()
            self.renderFullPopoverIfShown()
        }
        popoverVC.onSelectFloatingBadgeMode = { [weak self] mode in
            guard let self else { return }
            self.floatingBadgeMode = mode
            self.defaults.set(mode.rawValue, forKey: "floatingBadgeMode")
            self.syncFloatingBadgeVisibility()
            self.renderFullPopoverIfShown()
        }
        popoverVC.onToggleLaunchAtLogin = { [weak self] enabled in
            guard let self else { return }
            self.setLaunchAtLogin(enabled)
            self.renderFullPopoverIfShown()
        }
        popoverVC.onQuitApp = {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Launch at Login (SMAppService) & All-Spaces Floating Mini Capsule

    private var isLaunchAtLoginEnabled: Bool {
        guard canUseUserNotifications else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard canUseUserNotifications else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 未签名调试态下保持静默兼容
        }
    }

    private func defaultFloatingBadgeOrigin() -> NSPoint {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.maxX - 118, y: visible.maxY - 40)
    }

    /// 检测系统菜单栏图标是否因刘海屏（Camera Notch）、灵动岛挂件、过多常驻图标挤压或全屏空间而被 macOS 隐藏
    private func isMenuBarIconLikelyOccluded() -> Bool {
        guard let btn = statusItem?.button, let btnWin = btn.window else {
            return true
        }
        if !btnWin.occlusionState.contains(.visible) {
            return true
        }
        let f = btnWin.frame
        if f.width < 4 || f.height < 4 {
            return true
        }
        if let screen = btnWin.screen ?? NSScreen.main {
            // 全屏应用空间下菜单栏自动收起时（visibleFrame 顶部逼近屏幕物理顶部），自动启用右上角微胶囊
            if screen.frame.maxY - screen.visibleFrame.maxY < 6 {
                return true
            }
            // 带刘海 MacBook 上，若右侧菜单栏已塞满图标或挂有灵动岛组件（图标被挤到右半区最左端 68pt 危险区或越过刘海右缘），判定为遮挡风险
            if let auxRight = screen.auxiliaryTopRightArea, f.minX < auxRight.minX + 68 {
                return true
            }
        }
        return false
    }

    private func syncFloatingBadgeVisibility() {
        let shouldShow: Bool
        switch floatingBadgeMode {
        case .always:
            shouldShow = true
        case .off:
            shouldShow = false
        case .autoWhenOccluded:
            if popover.isShown, let existing = floatingBadgePanel, existing.isVisible {
                shouldShow = true
            } else {
                shouldShow = isMenuBarIconLikelyOccluded()
            }
        }

        if shouldShow {
            let panel: FloatingStatusBadgePanel
            if let existing = floatingBadgePanel {
                panel = existing
            } else {
                let origin: NSPoint
                if defaults.object(forKey: "floatingBadgeOriginX") != nil {
                    origin = NSPoint(
                        x: defaults.double(forKey: "floatingBadgeOriginX"),
                        y: defaults.double(forKey: "floatingBadgeOriginY")
                    )
                } else {
                    origin = defaultFloatingBadgeOrigin()
                }
                let created = FloatingStatusBadgePanel(initialOrigin: origin)
                created.onClickBadge = { [weak self] in
                    self?.togglePopoverFromFloatingBadge()
                }
                created.onOriginSaved = { [weak self] newOrigin in
                    guard let self else { return }
                    self.defaults.set(Double(newOrigin.x), forKey: "floatingBadgeOriginX")
                    self.defaults.set(Double(newOrigin.y), forKey: "floatingBadgeOriginY")
                }
                self.floatingBadgePanel = created
                panel = created
            }
            clampFloatingBadgeToVisibleScreenIfNeeded()
            let sprite = SpriteRenderer.renderSpriteFrame(
                state: latestSnapshot.topState,
                pack: activePack,
                frame: frameIndex,
                pointSize: 18,
                showStatusDot: false
            )
            panel.updateBadge(
                sprite: sprite,
                amountText: currentMenuMoneyText(),
                state: latestSnapshot.topState
            )
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
        } else {
            floatingBadgePanel?.orderOut(nil)
        }
    }

    private func clampFloatingBadgeToVisibleScreenIfNeeded() {
        guard let panel = floatingBadgePanel else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let frame = panel.frame
        let onAnyScreen = screens.contains { $0.visibleFrame.intersects(frame) }
        if !onAnyScreen {
            panel.setFrameOrigin(defaultFloatingBadgeOrigin())
        }
    }

    // MARK: - Popover Show & Reliable Outside-Click Auto-Dismissal (.accessory App)

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let btn = statusItem.button else { return }
        if popover.isShown {
            closePopover(sender)
        } else {
            openPopover(relativeToView: btn)
        }
    }

    private func togglePopoverFromFloatingBadge() {
        guard let badge = floatingBadgePanel else { return }
        if popover.isShown {
            closePopover(nil)
        } else {
            openPopover(relativeToView: badge.anchorView)
        }
    }

    private func openPopover(relativeToView anchorView: NSView) {
        isShowingModalPanel = false
        popover.behavior = .transient
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        NSApplication.shared.activate()
        popoverVC.view.window?.makeKey()
        installOutsideClickMonitor()
        renderFullPopoverIfShown()
        scheduleBackgroundReload(refreshTerminals: true, immediate: true)
    }

    private func closePopover(_ sender: Any?) {
        popoverVC.forceDismissAllOverlays()
        isShowingModalPanel = false
        popover.behavior = .transient
        removeOutsideClickMonitor()
        if popover.isShown {
            popover.performClose(sender)
        }
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        if isShowingModalPanel || popoverVC.isApiKeyModalVisible {
            return false
        }
        return true
    }

    func popoverDidClose(_ notification: Notification) {
        isShowingModalPanel = false
        popover.behavior = .transient
        removeOutsideClickMonitor()
        syncFloatingBadgeVisibility()
    }

    @objc private func handleAppDidResignActive(_ notification: Notification) {
        statusItem?.isVisible = true
        syncFloatingBadgeVisibility()
        guard popover.isShown,
              !isShowingModalPanel,
              !popoverVC.isApiKeyModalVisible,
              NSApplication.shared.modalWindow == nil else { return }
        closePopover(nil)
    }

    @objc private func handleWorkspaceDidActivateApp(_ notification: Notification) {
        statusItem?.isVisible = true
        syncFloatingBadgeVisibility()
        guard popover.isShown,
              !isShowingModalPanel,
              !popoverVC.isApiKeyModalVisible,
              NSApplication.shared.modalWindow == nil else { return }
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            closePopover(nil)
        }
    }

    @objc private func handleActiveSpaceOrScreenChanged(_ notification: Notification) {
        statusItem?.isVisible = true
        updateMenuBarStatusTextAndTooltip()
        clampFloatingBadgeToVisibleScreenIfNeeded()
        syncFloatingBadgeVisibility()
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            guard NSApplication.shared.modalWindow == nil else { return }
            // 当内嵌多 API-Key 管理卡片开启时，允许用户切换到浏览器/备忘录复制 sk-... 而不关闭弹窗
            guard !self.isShowingModalPanel, !self.popoverVC.isApiKeyModalVisible else { return }

            let mouseScreenPt = NSEvent.mouseLocation
            if let btnWin = self.statusItem?.button?.window,
               btnWin.frame.insetBy(dx: -4, dy: -4).contains(mouseScreenPt) {
                return
            }
            if let badgeWin = self.floatingBadgePanel, badgeWin.isVisible,
               badgeWin.frame.insetBy(dx: -4, dy: -4).contains(mouseScreenPt) {
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
            let showDot = (self.menuBarDisplayMode == .iconOnly)
            let menuSprite = SpriteRenderer.renderSpriteFrame(
                state: state,
                pack: self.activePack,
                frame: self.frameIndex,
                pointSize: 18,
                showStatusDot: showDot
            )
            btn.image = menuSprite

            if let badge = self.floatingBadgePanel, badge.isVisible {
                let badgeSprite = showDot
                    ? SpriteRenderer.renderSpriteFrame(
                        state: state,
                        pack: self.activePack,
                        frame: self.frameIndex,
                        pointSize: 18,
                        showStatusDot: false
                    )
                    : menuSprite
                badge.updateBadge(
                    sprite: badgeSprite,
                    amountText: self.currentMenuMoneyText(),
                    state: state
                )
            }

            if self.popover.isShown {
                self.popoverVC.tickAnimationFrame(
                    topState: state,
                    activePack: self.activePack,
                    frameIndex: self.frameIndex
                )
            }

            if self.tickCounter % 15 == 0 {
                self.updateMenuBarStatusTextAndTooltip()
                self.syncFloatingBadgeVisibility()
                if self.popover.isShown {
                    self.popoverVC.tickOneSecondTimers(
                        topState: state,
                        topEnteredAtMs: self.latestSnapshot.topStateEnteredAtMs
                    )
                }
            }

            if self.tickCounter % 60 == 0 {
                let needTermRefresh = self.popover.isShown
                self.scheduleBackgroundReload(refreshTerminals: needTermRefresh, immediate: true)
            }

            if self.tickCounter % (15 * 1800) == 0 {
                self.refreshExchangeRateOnly()
            }
        }
        if let animTimer {
            RunLoop.main.add(animTimer, forMode: .common)
        }
    }

    private func currentEffectiveSpendCny() -> Double {
        let safeRate = max(1.0, quota.usdToCnyRate)
        if let csv = csvReconciliation {
            return csv.currency == "USD" ? csv.totalCostInOriginalCurrency * safeRate : csv.totalCostInOriginalCurrency
        }
        return latestSnapshot.scoped(for: selectedKeyScopeId).billing.spurCostCny
    }

    private func currentMenuMoneyText() -> String {
        let safeRate = max(1.0, quota.usdToCnyRate)
        let effectiveCny = currentEffectiveSpendCny()
        return DeepSeekPricingEngine.formatMoney(
            amountCny: effectiveCny,
            mode: currencyMode,
            usdToCnyRate: safeRate,
            highPrecision: effectiveCny > 0 && effectiveCny < 0.1
        )
    }

    private func updateMenuBarStatusTextAndTooltip() {
        guard let statusItem, let btn = statusItem.button else { return }
        if !statusItem.isVisible {
            statusItem.isVisible = true
        }

        let state = latestSnapshot.topState
        let safeRate = max(1.0, quota.usdToCnyRate)
        let scoped = latestSnapshot.scoped(for: selectedKeyScopeId)
        let effectiveCny = currentEffectiveSpendCny()
        let menuMoneyStr = currentMenuMoneyText()

        switch menuBarDisplayMode {
        case .iconOnly:
            if statusItem.length != NSStatusItem.squareLength {
                statusItem.length = NSStatusItem.squareLength
            }
            if !btn.title.isEmpty {
                btn.title = ""
            }
            btn.imagePosition = .imageOnly

        case .compactAmount:
            if statusItem.length != NSStatusItem.variableLength {
                statusItem.length = NSStatusItem.variableLength
            }
            let rawVal = (currencyMode == .cny) ? effectiveCny : (effectiveCny / safeRate)
            let shortStr = rawVal >= 10.0
                ? "\(currencyMode.symbol)\(Int(rawVal.rounded()))"
                : String(format: "%@%.1f", currencyMode.symbol, rawVal)
            btn.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
            btn.title = " \(shortStr)"
            btn.imagePosition = .imageLeading

        case .fullStatus:
            if statusItem.length != NSStatusItem.variableLength {
                statusItem.length = NSStatusItem.variableLength
            }
            let fullStr = state.isActiveRunning ? " \(state.label) · \(menuMoneyStr)" : " \(menuMoneyStr)"
            btn.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
            btn.title = fullStr
            btn.imagePosition = .imageLeading
        }

        btn.image = SpriteRenderer.renderSpriteFrame(
            state: state,
            pack: activePack,
            frame: frameIndex,
            pointSize: 18,
            showStatusDot: menuBarDisplayMode == .iconOnly
        )

        let b = scoped.billing
        let fxInfo = String(
            format: "%@ · 今日精算 ¥%.4f · Cache %.1f%% · 汇率 $1=¥%.4f",
            scoped.title,
            b.spurCostCny,
            b.cacheHitRatePercent,
            safeRate
        )
        let dragHint = "按住 ⌘ 键可将图标向右拖到控制中心旁，防止切屏被菜单挤压"
        if let urgent = latestSnapshot.urgentSubTask {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let timerStr = TimeFormatters.liveStateTimerLabel(
                state: urgent.state,
                enteredAtMs: urgent.stateEnteredAtMs,
                nowMs: nowMs
            )
            btn.toolTip = "AgentSpur · \(urgent.title) (\(timerStr))\n\(fxInfo)\n\(dragHint)"
        } else {
            btn.toolTip = "AgentSpur 菜单栏精算监控\n\(fxInfo)\n\(dragHint)"
        }
    }

    private func renderFullPopoverIfShown() {
        guard popover.isShown else { return }
        popoverVC.renderSnapshot(
            snapshot: latestSnapshot,
            apiKeyProfiles: effectiveApiKeyProfiles,
            selectedKeyScopeId: selectedKeyScopeId,
            quota: quota,
            currencyMode: currencyMode,
            csvReconciliation: csvReconciliation,
            activePack: activePack,
            allPacks: allPacks,
            frameIndex: frameIndex,
            autoFocusEnabled: autoFocusEnabled,
            selectedWindowId: selectedRealWindowId,
            notificationsMuted: notificationsMuted,
            menuBarDisplayMode: menuBarDisplayMode,
            floatingBadgeMode: floatingBadgeMode,
            launchAtLoginEnabled: isLaunchAtLoginEnabled
        )
    }

    // MARK: - Background Debounced SQLite & Real Console Reload

    private func scheduleBackgroundReload(refreshTerminals: Bool, immediate: Bool = false) {
        debounceWorkItem?.cancel()
        let delay: TimeInterval = immediate ? 0.02 : 0.45

        let rateCopy = quota.usdToCnyRate
        let profilesCopy = apiKeyProfiles
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

                var pendingEvents: [AgentNotificationEvent] = []
                let snap = self.dbReader.readSnapshot(
                    usdToCnyRate: rateCopy,
                    configuredProfiles: profilesCopy,
                    realWindows: windows
                ) { ev in
                    pendingEvents.append(ev)
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let prevKeys = Set(self.effectiveApiKeyProfiles.map { $0.rawApiKey }.filter { !$0.isEmpty })
                    let changed = (snap != self.latestSnapshot)
                    self.latestSnapshot = snap
                    let nextKeys = Set(self.effectiveApiKeyProfiles.map { $0.rawApiKey }.filter { !$0.isEmpty })

                    // 若原本选中的分组已不存在，自动平滑回退至全部 Key
                    if self.selectedKeyScopeId != APIKeyProfile.allKeysId,
                       !snap.availableKeyScopes.contains(where: { $0.keyId == self.selectedKeyScopeId }) {
                        self.selectedKeyScopeId = APIKeyProfile.allKeysId
                    }

                    for ev in pendingEvents {
                        self.deliverAgentNotification(event: ev, forcePlay: false)
                    }
                    if changed {
                        self.updateMenuBarStatusTextAndTooltip()
                        self.renderFullPopoverIfShown()
                    }
                    if nextKeys != prevKeys || (self.quota.apiTotalBalance == nil && !nextKeys.isEmpty && changed) {
                        self.refreshBalanceForActiveKeyProfile()
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

        var watchDirs: [String] = [dirPath]
        let configDir = ("~/.config/opencode" as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: configDir), !watchDirs.contains(configDir) {
            watchDirs.append(configDir)
        }

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = watchDirs as CFArray
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

    // MARK: - Online Exchange Rate + Per-Key Balance Refresh (`⌘R`)

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
        refreshBalanceForActiveKeyProfile()
    }

    private func refreshBalanceForActiveKeyProfile() {
        let allEffective = effectiveApiKeyProfiles
        let matchedProfile: APIKeyProfile?
        if selectedKeyScopeId == APIKeyProfile.allKeysId {
            matchedProfile = allEffective.first(where: { !$0.rawApiKey.isEmpty })
        } else {
            matchedProfile = allEffective.first(where: { $0.id == selectedKeyScopeId && !$0.rawApiKey.isEmpty })
                ?? allEffective.first(where: { !$0.rawApiKey.isEmpty })
        }

        let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? ""
        let effectiveKey = matchedProfile?.rawApiKey ?? (selectedKeyScopeId == APIKeyProfile.allKeysId ? envKey : "")

        guard !effectiveKey.isEmpty, let url = URL(string: "https://api.deepseek.com/user/balance") else {
            quota.apiTotalBalance = nil
            quota.balanceSourceLabel = ""
            updateMenuBarStatusTextAndTooltip()
            renderFullPopoverIfShown()
            return
        }

        let sourceDesc: String
        if let prof = matchedProfile {
            let shortTag = prof.maskedKey.isEmpty ? prof.name : prof.maskedKey
            if let autoSrc = prof.autoSource, !autoSrc.isEmpty {
                sourceDesc = "官方接口 · \(shortTag) (\(autoSrc))"
            } else {
                sourceDesc = "官方接口 · \(shortTag)"
            }
        } else {
            sourceDesc = "官方接口 · \(APIKeyProfile.makeMasked(effectiveKey)) (ENV)"
        }

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
                    : "Paid \(paidStr)"
                DispatchQueue.main.async {
                    self.quota.apiTotalBalance = totalVal
                    self.quota.apiCurrency = curr
                    self.quota.walletBreakdownLabel = walletLabel
                    self.quota.balanceSourceLabel = sourceDesc
                    self.updateMenuBarStatusTextAndTooltip()
                    self.renderFullPopoverIfShown()
                }
                return
            }
            DispatchQueue.main.async {
                self.quota.apiTotalBalance = nil
                self.quota.balanceSourceLabel = ""
                self.updateMenuBarStatusTextAndTooltip()
                self.renderFullPopoverIfShown()
            }
        }.resume()
    }

    // MARK: - In-Popover Multi API-Key Persistence + Standard Edit Menu (Cmd+C / Cmd+V / Cmd+A)

    private func installStandardEditMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        NSApplication.shared.mainMenu = mainMenu
    }

    private func upsertApiKeyProfile(name: String, rawSecret: String, directoryKeyword: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "默认主Key" : trimmedName
        let cleanSecret = rawSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let masked = cleanSecret.isEmpty ? "" : APIKeyProfile.makeMasked(cleanSecret)
        let cleanKeyword = directoryKeyword.trimmingCharacters(in: .whitespacesAndNewlines)

        let matchedAuto = latestSnapshot.effectiveProfiles.first(where: {
            $0.name == finalName || (!cleanSecret.isEmpty && $0.rawApiKey == cleanSecret)
        })

        if let idx = apiKeyProfiles.firstIndex(where: {
            $0.name == finalName || (!cleanSecret.isEmpty && $0.rawApiKey == cleanSecret)
        }) {
            if !cleanSecret.isEmpty || apiKeyProfiles[idx].rawApiKey.isEmpty {
                apiKeyProfiles[idx].rawApiKey = cleanSecret
                apiKeyProfiles[idx].maskedKey = masked
            }
            apiKeyProfiles[idx].name = finalName
            apiKeyProfiles[idx].directoryKeyword = cleanKeyword
            if let auto = matchedAuto, apiKeyProfiles[idx].providerId.isEmpty {
                apiKeyProfiles[idx].providerId = auto.providerId
            }
            selectedKeyScopeId = apiKeyProfiles[idx].id
        } else {
            let newId = matchedAuto?.id ?? "key-\(UUID().uuidString.prefix(8))"
            let finalSecret = cleanSecret.isEmpty ? (matchedAuto?.rawApiKey ?? "") : cleanSecret
            let finalMasked = finalSecret.isEmpty ? "" : APIKeyProfile.makeMasked(finalSecret)
            let profile = APIKeyProfile(
                id: newId,
                name: finalName,
                rawApiKey: finalSecret,
                maskedKey: finalMasked,
                directoryKeyword: cleanKeyword,
                providerId: matchedAuto?.providerId ?? "",
                autoSource: matchedAuto?.autoSource
            )
            apiKeyProfiles.append(profile)
            selectedKeyScopeId = newId
        }

        defaults.set(selectedKeyScopeId, forKey: "selectedKeyScopeId")
        saveApiKeyProfiles()
        refreshExchangeRateAndQuota(refreshTerminals: false)
    }

    private func deleteApiKeyProfile(profileId: String) {
        apiKeyProfiles.removeAll(where: { $0.id == profileId })
        if selectedKeyScopeId == profileId {
            selectedKeyScopeId = APIKeyProfile.allKeysId
            defaults.set(selectedKeyScopeId, forKey: "selectedKeyScopeId")
        }
        saveApiKeyProfiles()
        refreshExchangeRateAndQuota(refreshTerminals: false)
    }

    // MARK: - Reliable Native Audio + macOS Notification Delivery

    private func deliverAgentNotification(event: AgentNotificationEvent, forcePlay: Bool) {
        guard forcePlay || !notificationsMuted else { return }

        // 1. 直接通过 AppKit NSSound 播放 macOS 原生系统音效（即使未授予通知声音权限或前台焦点状态下也 100% 响亮清脆）
        let soundName: String
        let titleText: String
        switch event.kind {
        case .completed:
            soundName = "Glass"
            titleText = "AgentSpur · 任务已完成"
        case .confirmNeeded:
            soundName = "Ping"
            titleText = "AgentSpur · 等待你的确认"
        case .errorOccurred:
            soundName = "Basso"
            titleText = "AgentSpur · 任务执行出错"
        }
        if let sysSound = NSSound(named: NSSound.Name(soundName)) {
            sysSound.stop()
            sysSound.play()
        } else {
            NSSound.beep()
        }

        // 2. 投递原生 macOS 通知中心横幅 (配合 UNUserNotificationCenterDelegate 在前台亦可弹出)
        guard canUseUserNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = titleText
        content.body = event.taskTitle
        content.sound = nil // 声音已由上方 NSSound 精准播放，避免双重回声
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
