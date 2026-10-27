import AppKit
import CoreServices
import Foundation
import UserNotifications

@main
final class AgentSpurApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let popoverVC = StatusPopoverViewController()
    private let dbReader = OpenCodeDBReader()

    private var animTimer: Timer?
    private var fsEventStream: FSEventStreamRef?
    private var frameIndex: Int = 0
    private var tickCounter: Int = 0

    private var latestSnapshot: OpenCodeDBSnapshot!
    private var frontmostHint: FrontmostTerminalHint?

    private var customPacks: [DeepSeekRolePack] = []
    private var activePackId: String = "pack-gin-droplet"
    private var silentAlertEnabled: Bool = true
    private var autoFocusEnabled: Bool = true
    private var autoFocusTarget: AutoFocusWindowTarget = .opencodeTUI

    private var quota = QuotaSnapshot(
        displayBalance: "统计中",
        resetTimeLabel: "04:00重置",
        lastRefreshedHHMM: TimeFormatters.currentHHMM()
    )

    private let defaults = UserDefaults.standard

    static func main() {
        // 支持在打包 DMG 时直接调用二进制渲染高清 1024x1024 AppIcon PNG：
        // AgentSpur --export-icon /path/to/icon_1024.png
        let args = CommandLine.arguments
        if let flagIdx = args.firstIndex(of: "--export-icon"), flagIdx + 1 < args.count {
            let outputPath = args[flagIdx + 1]
            let ok = SpriteRenderer.exportHighResAppIconPNG(to: outputPath, pixelSize: 1024)
            exit(ok ? 0 : 1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // 纯菜单栏轻量应用，无 Dock 图标
        let delegate = AgentSpurApp()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadPreferences()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

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

        wirePopoverCallbacks()
        reloadDatabaseSnapshot()
        refreshQuotaBalance()
        start15FPSRunLoop()
        startFSEventsReadOnlyWatcher()
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        if let rawTarget = defaults.string(forKey: "autoFocusTarget"),
           let target = AutoFocusWindowTarget(rawValue: rawTarget) {
            autoFocusTarget = target
        }
        if let savedPackId = defaults.string(forKey: "activePackId") {
            activePackId = savedPackId
        }
        if let data = defaults.data(forKey: "customPacksData"),
           let decoded = try? JSONDecoder().decode([DeepSeekRolePack].self, from: data) {
            customPacks = decoded
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
            self?.reloadDatabaseSnapshot()
            self?.refreshQuotaBalance()
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
                self.frontmostHint = TerminalBridge.inspectFrontmostTerminal()
            }
        }
        popoverVC.onChangeAutoFocusTarget = { [weak self] target in
            guard let self else { return }
            self.autoFocusTarget = target
            self.defaults.set(target.rawValue, forKey: "autoFocusTarget")
        }
        popoverVC.onSelectPack = { [weak self] selectedName in
            guard let self,
                  let found = self.allPacks.first(where: { $0.name == selectedName }) else { return }
            self.activePackId = found.id
            self.defaults.set(found.id, forKey: "activePackId")
        }
        popoverVC.onImportCustomPack = { [weak self] pack in
            guard let self else { return }
            self.customPacks.removeAll(where: { $0.id == pack.id })
            self.customPacks.append(pack)
            self.activePackId = pack.id
            self.defaults.set(pack.id, forKey: "activePackId")
            self.saveCustomPacks()
        }
        popoverVC.onConfigureApiKey = { [weak self] in
            self?.promptForDeepSeekApiKey()
        }
        popoverVC.onQuitApp = {
            NSApplication.shared.terminate(nil)
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let btn = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            reloadDatabaseSnapshot()
            if autoFocusEnabled {
                frontmostHint = TerminalBridge.inspectFrontmostTerminal()
            }
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            syncPopoverIfVisible()
        }
    }

    // MARK: - 15 FPS Native Menu Bar Animation & Hover Tooltip

    private func start15FPSRunLoop() {
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            guard let self, let btn = self.statusItem.button else { return }
            self.frameIndex = (self.frameIndex + 1) % 15
            self.tickCounter += 1

            // 每 2 秒轻量轮询一次前台终端提示（仅在浮层展开且开启自动聚焦时）
            if self.popover.isShown && self.autoFocusEnabled && self.tickCounter % 30 == 0 {
                self.frontmostHint = TerminalBridge.inspectFrontmostTerminal()
            }

            let state = self.latestSnapshot.topState
            btn.image = SpriteRenderer.renderSpriteFrame(
                state: state,
                pack: self.activePack,
                frame: self.frameIndex,
                pointSize: 18
            )
            btn.imagePosition = .imageLeading

            let titleStr = " \(state.label) · \(self.quota.displayBalance) · \(self.quota.resetTimeLabel.replacingOccurrences(of: "重置", with: ""))"
            btn.attributedTitle = NSAttributedString(
                string: titleStr,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
                ]
            )

            // 菜单栏 Hover Tooltip：展示当前最紧急子任务名称、所属终端与进入当前状态时长
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            if let urgent = self.latestSnapshot.urgentSubTask {
                let timerStr = TimeFormatters.liveStateTimerLabel(
                    state: urgent.state,
                    enteredAtMs: urgent.stateEnteredAtMs,
                    nowMs: nowMs
                )
                btn.toolTip = "AgentSpur 最急子任务：\(urgent.title)\n终端：\(urgent.targetApp.rawValue) · \(timerStr)"
            } else {
                btn.toolTip = "AgentSpur · opencode.db 实时只读监控 (点击展开会话一览)"
            }

            if self.popover.isShown {
                self.syncPopoverIfVisible()
            }
        }
        if let animTimer {
            RunLoop.main.add(animTimer, forMode: .common)
        }
    }

    private func syncPopoverIfVisible() {
        popoverVC.renderState(
            snapshot: latestSnapshot,
            quota: quota,
            activePack: activePack,
            allPacks: allPacks,
            frameIndex: frameIndex,
            autoFocusEnabled: autoFocusEnabled,
            autoFocusTarget: autoFocusTarget,
            frontmostHint: frontmostHint,
            silentAlertEnabled: silentAlertEnabled
        )
    }

    // MARK: - Read-Only opencode.db Reload & FSEvents

    private func reloadDatabaseSnapshot() {
        latestSnapshot = dbReader.readSnapshot { [weak self] completedTitle in
            self?.postSilentCompletionNotification(taskTitle: completedTitle)
        }
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
            DispatchQueue.main.async {
                app.reloadDatabaseSnapshot()
            }
        }

        if let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.35,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) {
            fsEventStream = stream
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    // MARK: - Quota Refresh (`⌘R`) & Silent Completion Notification

    private func refreshQuotaBalance() {
        quota.lastRefreshedHHMM = TimeFormatters.currentHHMM()

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
                   let balance = first["total_balance"] as? String {
                    let symbol = (first["currency"] as? String) == "CNY" ? "¥" : "$"
                    DispatchQueue.main.async {
                        self.quota.displayBalance = "\(symbol)\(balance)"
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.quota.displayBalance = String(format: "已用 $%.2f", self.latestSnapshot.totalSpentUsd)
                }
            }.resume()
        } else {
            quota.displayBalance = String(format: "已用 $%.2f", latestSnapshot.totalSpentUsd)
        }
    }

    private func promptForDeepSeekApiKey() {
        let alert = NSAlert()
        alert.messageText = "配置 DeepSeek 余额查询 Key (可选)"
        alert.informativeText = "填入后按 ⌘R 将直连 DeepSeek 官方接口在菜单栏显示实时剩余额度；留空则离线统计 opencode.db 本地累计花费。"
        alert.addButton(withTitle: "保存并刷新")
        alert.addButton(withTitle: "取消")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = "sk-..."
        input.stringValue = defaults.string(forKey: "deepseekApiKey") ?? ""
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            let trimmed = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: "deepseekApiKey")
            refreshQuotaBalance()
        }
    }

    private func postSilentCompletionNotification(taskTitle: String) {
        guard silentAlertEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "AgentSpur · 任务已完成"
        content.body = taskTitle
        content.sound = nil // 严格静音提醒
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
