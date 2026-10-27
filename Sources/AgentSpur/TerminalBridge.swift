import AppKit
import Darwin
import Foundation

enum TerminalBridge {
    private static let terminalBundleIds: [String] = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "org.alacritty"
    ]

    /// 探测本机当前真实打开的控制台窗口与标签页（支持 macOS Terminal.app、iTerm2、Darwin TMPDIR tmux 及 ps/lsof 零 TCC 兜底，零假数据）
    static func discoverRealWindows() -> [RealTerminalWindow] {
        let (isAppleTerminalRunning, isITermRunning, frontBundleId): (Bool, Bool, String) = {
            if Thread.isMainThread {
                let apps = NSWorkspace.shared.runningApplications
                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
                return (
                    apps.contains { $0.bundleIdentifier == "com.apple.Terminal" },
                    apps.contains { $0.bundleIdentifier == "com.googlecode.iterm2" },
                    front
                )
            } else {
                return DispatchQueue.main.sync {
                    let apps = NSWorkspace.shared.runningApplications
                    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
                    return (
                        apps.contains { $0.bundleIdentifier == "com.apple.Terminal" },
                        apps.contains { $0.bundleIdentifier == "com.googlecode.iterm2" },
                        front
                    )
                }
            }
        }()

        let isAnyTermFrontmost = terminalBundleIds.contains(frontBundleId)

        // 1. 先探测真实 tmux panes（包含 macOS 特有的 NSTemporaryDirectory()/tmux-<uid>/default 套接字路径）
        let tmuxDirsBySession = queryTmuxSessionPaths()

        var discovered: [RealTerminalWindow] = []

        // 2. 尝试通过 AppleScript 获取 Terminal.app / iTerm2 真实打开的窗口与标签页
        if isAppleTerminalRunning {
            let termFront = (frontBundleId == "com.apple.Terminal")
            discovered.append(contentsOf: queryAppleTerminalTabs(isFrontmost: termFront, tmuxPaths: tmuxDirsBySession))
        }

        if isITermRunning {
            let itermFront = (frontBundleId == "com.googlecode.iterm2")
            discovered.append(contentsOf: queryITerm2Tabs(isFrontmost: itermFront, tmuxPaths: tmuxDirsBySession))
        }

        // 3. 若 macOS 尚未授予 Automation 权限或用户在 Ghostty / Warp / Kitty / tmux 中运行，使用真实 tmux panes 填充
        if discovered.isEmpty && !tmuxDirsBySession.isEmpty {
            var idx = 1
            for (sessName, info) in tmuxDirsBySession.sorted(by: { $0.key < $1.key }) {
                let folderName = (info.path as NSString).lastPathComponent
                let cleanTitle = info.title.isEmpty
                    ? (folderName.isEmpty ? sessName : "\(sessName) (\(folderName))")
                    : "\(sessName) · \(info.title)"
                discovered.append(
                    RealTerminalWindow(
                        id: "tmux:\(sessName):\(idx)",
                        appKind: .tmux,
                        windowId: sessName,
                        tabIndex: idx,
                        title: cleanTitle,
                        workingDirectory: info.path,
                        isActiveTab: info.isActive,
                        isFrontmostApp: isAnyTermFrontmost && info.isActive
                    )
                )
                idx += 1
            }
        }

        // 4. 零 TCC 权限终极兜底：通过 /bin/ps + lsof 扫描本机 TTY 上真实活跃的 tmux / opencode 进程
        if discovered.isEmpty {
            discovered.append(contentsOf: queryLiveConsoleProcessesViaPS(isAnyTermFrontmost: isAnyTermFrontmost))
        }

        return discovered
    }

    /// 将 opencode.db 中的真实会话 (directory + title) 与探测到的本机真实终端标签页精准配对
    static func matchSessionToWindow(
        directory: String,
        sessionTitle: String,
        windows: [RealTerminalWindow]
    ) -> RealTerminalWindow? {
        guard !windows.isEmpty else { return nil }

        let home = NSHomeDirectory()
        let normDir = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        let tildeDir = normDir.hasPrefix(home)
            ? "~" + String(normDir.dropFirst(home.count))
            : normDir
        let dirBase = (normDir as NSString).lastPathComponent.lowercased()
        let cleanSessionTitle = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var bestWindow: RealTerminalWindow?
        var bestScore = 0

        for win in windows {
            var score = 0
            let winTitleLower = win.title.lowercased()
            let winDirLower = win.workingDirectory.lowercased()
            let winIdLower = win.windowId.lowercased()

            if !normDir.isEmpty {
                if !winDirLower.isEmpty && (winDirLower == normDir.lowercased() || winDirLower.contains(normDir.lowercased())) {
                    score += 130
                }
                if winTitleLower.contains(normDir.lowercased()) || (!tildeDir.isEmpty && winTitleLower.contains(tildeDir.lowercased())) {
                    score += 115
                }
                if dirBase.count >= 3 && (winTitleLower.contains(dirBase) || winIdLower.contains(dirBase) || winDirLower.hasSuffix("/" + dirBase)) {
                    score += 75
                }
            }

            if cleanSessionTitle.count >= 4 {
                let prefixKey = String(cleanSessionTitle.prefix(10))
                if winTitleLower.contains(prefixKey) {
                    score += 55
                }
            }

            if score > 0 && (winTitleLower.contains("opencode") || winIdLower.contains("oc-")) {
                score += 20
            }
            if score > 0 && win.isActiveTab {
                score += 8
            }

            if score > bestScore {
                bestScore = score
                bestWindow = win
            }
        }

        return bestScore >= 50 ? bestWindow : nil
    }

    /// 点击任务行时，精准激活并切换到真实对应的 Terminal.app / iTerm2 / tmux 所在终端窗口
    static func jumpToRealWindow(_ window: RealTerminalWindow?, fallbackDirectory: String) {
        if let win = window {
            switch win.appKind {
            case .appleTerminal:
                let scriptSrc = """
                tell application "Terminal"
                    activate
                    repeat with w in windows
                        if (id of w as string) is "\(win.windowId)" then
                            set index of w to 1
                            if (count of tabs of w) >= \(win.tabIndex) then
                                set selected of tab \(win.tabIndex) of w to true
                            end if
                            return
                        end if
                    end repeat
                end tell
                """
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = runAppleScript(scriptSrc)
                }
                return

            case .iterm2:
                let scriptSrc = """
                tell application "iTerm2"
                    activate
                    repeat with w in windows
                        if (id of w as string) is "\(win.windowId)" then
                            select w
                            if (count of tabs of w) >= \(win.tabIndex) then
                                select tab \(win.tabIndex) of w
                            end if
                            return
                        end if
                    end repeat
                end tell
                """
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = runAppleScript(scriptSrc)
                }
                return

            case .tmux:
                // 若在 Terminal.app 中跑 tmux，尝试切到包含该会话名的标签页；无论是否有 AppleEvents 权限都立即前置终端应用
                let escapedSess = win.windowId.replacingOccurrences(of: "\"", with: "")
                if !escapedSess.isEmpty {
                    let scriptSrc = """
                    tell application "Terminal"
                        if running then
                            activate
                            repeat with w in windows
                                set tCount to count of tabs of w
                                repeat with i from 1 to tCount
                                    set t to tab i of w
                                    if (name of w as string) contains "\(escapedSess)" then
                                        set index of w to 1
                                        set selected of t to true
                                        return
                                    end if
                                end repeat
                            end repeat
                        end if
                    end tell
                    """
                    DispatchQueue.global(qos: .userInitiated).async {
                        _ = runAppleScript(scriptSrc)
                    }
                }
            }
        }

        // 温和激活本机正在运行的任意主力终端应用
        let running = NSWorkspace.shared.runningApplications
        for bid in terminalBundleIds {
            if let app = running.first(where: { $0.bundleIdentifier == bid }) {
                _ = app.activate()
                return
            }
        }
    }

    // MARK: - Private Native Terminal, tmux & Zero-TCC PS Inspectors

    private static let fieldSep = "|||"

    private static func queryAppleTerminalTabs(
        isFrontmost: Bool,
        tmuxPaths: [String: (path: String, title: String, isActive: Bool)]
    ) -> [RealTerminalWindow] {
        let scriptSrc = """
        tell application "Terminal"
            if (count of windows) is 0 then return ""
            set outLines to ""
            set frontWinId to ""
            try
                set frontWinId to (id of front window as string)
            end try
            repeat with w in windows
                try
                    set wid to (id of w as string)
                    set wName to (name of w as string)
                    set tCount to count of tabs of w
                    repeat with i from 1 to tCount
                        set t to tab i of w
                        set isSel to (selected of t as string)
                        set cTitle to ""
                        try
                            set rawCustom to custom title of t
                            if rawCustom is not missing value then
                                set cTitle to (rawCustom as string)
                            end if
                        end try
                        set rowStr to wid & "|||" & (i as string) & "|||" & isSel & "|||" & frontWinId & "|||" & wName & "|||" & cTitle
                        set outLines to outLines & rowStr & linefeed
                    end repeat
                end try
            end repeat
            return outLines
        end tell
        """

        guard let raw = runAppleScript(scriptSrc), !raw.isEmpty else { return [] }
        var results: [RealTerminalWindow] = []

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let cols = trimmed.components(separatedBy: fieldSep)
            guard cols.count >= 5 else { continue }

            let wid = cols[0]
            let tabIdx = Int(cols[1]) ?? 1
            let isSelected = (cols[2] == "true")
            let frontWinId = cols[3]
            let wName = cols[4]
            let customTitle = cols.count > 5 ? cols[5] : ""

            let displayTitle: String
            if isSelected && !wName.isEmpty {
                displayTitle = wName
            } else if !customTitle.isEmpty {
                displayTitle = customTitle
            } else {
                displayTitle = wName
            }

            let resolvedDir = extractDirectoryFromTitleOrTmux(title: displayTitle, tmuxPaths: tmuxPaths)

            results.append(
                RealTerminalWindow(
                    id: "Terminal:\(wid):\(tabIdx)",
                    appKind: .appleTerminal,
                    windowId: wid,
                    tabIndex: tabIdx,
                    title: displayTitle,
                    workingDirectory: resolvedDir,
                    isActiveTab: isSelected && (frontWinId.isEmpty || wid == frontWinId),
                    isFrontmostApp: isFrontmost && (frontWinId.isEmpty || wid == frontWinId) && isSelected
                )
            )
        }
        return results
    }

    private static func queryITerm2Tabs(
        isFrontmost: Bool,
        tmuxPaths: [String: (path: String, title: String, isActive: Bool)]
    ) -> [RealTerminalWindow] {
        let scriptSrc = """
        tell application "iTerm2"
            if (count of windows) is 0 then return ""
            set outLines to ""
            set currWinId to ""
            try
                set currWinId to (id of current window as string)
            end try
            repeat with w in windows
                try
                    set wid to (id of w as string)
                    set currTab to current tab of w
                    set tCount to count of tabs of w
                    repeat with i from 1 to tCount
                        set t to item i of tabs of w
                        set isSel to ((t is currTab) as string)
                        set sName to (name of current session of t as string)
                        set rowStr to wid & "|||" & (i as string) & "|||" & isSel & "|||" & currWinId & "|||" & sName
                        set outLines to outLines & rowStr & linefeed
                    end repeat
                end try
            end repeat
            return outLines
        end tell
        """

        guard let raw = runAppleScript(scriptSrc), !raw.isEmpty else { return [] }
        var results: [RealTerminalWindow] = []

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let cols = trimmed.components(separatedBy: fieldSep)
            guard cols.count >= 5 else { continue }

            let wid = cols[0]
            let tabIdx = Int(cols[1]) ?? 1
            let isSelected = (cols[2] == "true")
            let currWinId = cols[3]
            let sName = cols[4]
            let resolvedDir = extractDirectoryFromTitleOrTmux(title: sName, tmuxPaths: tmuxPaths)

            results.append(
                RealTerminalWindow(
                    id: "iTerm2:\(wid):\(tabIdx)",
                    appKind: .iterm2,
                    windowId: wid,
                    tabIndex: tabIdx,
                    title: sName,
                    workingDirectory: resolvedDir,
                    isActiveTab: isSelected && (currWinId.isEmpty || wid == currWinId),
                    isFrontmostApp: isFrontmost && (currWinId.isEmpty || wid == currWinId) && isSelected
                )
            )
        }
        return results
    }

    private static func extractDirectoryFromTitleOrTmux(
        title: String,
        tmuxPaths: [String: (path: String, title: String, isActive: Bool)]
    ) -> String {
        for (sessName, info) in tmuxPaths where title.contains(sessName) {
            return info.path
        }

        let tokens = title.components(separatedBy: .whitespaces)
        if let cIdx = tokens.firstIndex(of: "-c"), cIdx + 1 < tokens.count {
            return (tokens[cIdx + 1] as NSString).expandingTildeInPath
        }
        for tok in tokens {
            if tok.hasPrefix("~/") || tok.hasPrefix("/Users/") {
                return (tok as NSString).expandingTildeInPath
            }
        }
        return ""
    }

    /// 兼容 macOS Darwin NSTemporaryDirectory (`/var/folders/.../T/tmux-<uid>/default`) 与 `/tmp/tmux-<uid>/default`
    private static func queryTmuxSessionPaths() -> [String: (path: String, title: String, isActive: Bool)] {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        guard let tmuxBin = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return [:]
        }

        let fmtArg = "#{session_name}|||#{pane_current_path}|||#{pane_title}|||#{window_active}"
        let uid = getuid()
        let darwinTmpSocket = (NSTemporaryDirectory() as NSString).appendingPathComponent("tmux-\(uid)/default")

        var socketCandidates: [[String]] = [
            ["-S", darwinTmpSocket, "list-panes", "-a", "-F", fmtArg],
            ["list-panes", "-a", "-F", fmtArg],
            ["-S", "/tmp/tmux-\(uid)/default", "list-panes", "-a", "-F", fmtArg],
            ["-S", "/private/tmp/tmux-\(uid)/default", "list-panes", "-a", "-F", fmtArg]
        ]

        // 若 /tmp 或 Darwin TMPDIR 下有自定义命名的套接字（如 tmux -L custom），一并枚举
        for baseDir in [(NSTemporaryDirectory() as NSString).appendingPathComponent("tmux-\(uid)"), "/tmp/tmux-\(uid)"] {
            if let socks = try? FileManager.default.contentsOfDirectory(atPath: baseDir) {
                for s in socks where s != "default" {
                    let fullSock = (baseDir as NSString).appendingPathComponent(s)
                    socketCandidates.append(["-S", fullSock, "list-panes", "-a", "-F", fmtArg])
                }
            }
        }

        var map: [String: (path: String, title: String, isActive: Bool)] = [:]
        for args in socketCandidates {
            guard let text = runSubprocess(executable: tmuxBin, arguments: args), !text.isEmpty else {
                continue
            }
            for line in text.components(separatedBy: .newlines) {
                let parts = line.components(separatedBy: fieldSep)
                guard parts.count >= 4 else { continue }
                let sess = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let path = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let pTitle = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                let active = (parts[3].trimmingCharacters(in: .whitespacesAndNewlines) == "1")
                if !sess.isEmpty {
                    // 若同一 session 有多个 pane，优先保留 active pane 的路径与标题
                    if let existing = map[sess] {
                        if active && !existing.isActive {
                            map[sess] = (path, pTitle, active)
                        }
                    } else {
                        map[sess] = (path, pTitle, active)
                    }
                }
            }
            if !map.isEmpty {
                break
            }
        }
        return map
    }

    /// 零 TCC 权限回退探测：当 AppleEvents 被系统拦截且未检出标准 tmux socket 时，直接从 /bin/ps 读取真实 TTY 上的 tmux / opencode 终端会话
    private static func queryLiveConsoleProcessesViaPS(isAnyTermFrontmost: Bool) -> [RealTerminalWindow] {
        guard let psText = runSubprocess(executable: "/bin/ps", arguments: ["-axo", "tty=,pid=,args="]),
              !psText.isEmpty else {
            return []
        }

        var found: [RealTerminalWindow] = []
        var seenKeys = Set<String>()
        var pidsNeedingCwd: [(idx: Int, pid: String)] = []

        for rawLine in psText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard tokens.count >= 3 else { continue }
            let tty = tokens[0]
            let pid = tokens[1]
            if tty == "??" || tty == "?" { continue }

            let cmdArgs = Array(tokens.dropFirst(2))
            let execBase = (cmdArgs[0] as NSString).lastPathComponent

            // 识别形如: tmux new-session -A -s oc-opencode-master -c ~/ai-setup/opencode-master opencode ...
            if execBase == "tmux" {
                var sessName = ""
                var workDir = ""
                for i in 0..<cmdArgs.count {
                    if (cmdArgs[i] == "-s" || cmdArgs[i] == "-t"), i + 1 < cmdArgs.count {
                        sessName = cmdArgs[i + 1]
                    } else if cmdArgs[i] == "-c", i + 1 < cmdArgs.count {
                        workDir = (cmdArgs[i + 1] as NSString).expandingTildeInPath
                    }
                }
                if !sessName.isEmpty || !workDir.isEmpty {
                    let key = sessName.isEmpty ? "tmux-\(tty)" : sessName
                    guard !seenKeys.contains(key) else { continue }
                    seenKeys.insert(key)
                    let idx = found.count + 1
                    let dirLabel = (workDir as NSString).lastPathComponent
                    let title = dirLabel.isEmpty ? "\(key) (\(tty))" : "\(key) · \(dirLabel)"
                    found.append(
                        RealTerminalWindow(
                            id: "tmux:\(key):\(idx)",
                            appKind: .tmux,
                            windowId: key,
                            tabIndex: idx,
                            title: title,
                            workingDirectory: workDir,
                            isActiveTab: idx == 1,
                            isFrontmostApp: isAnyTermFrontmost && idx == 1
                        )
                    )
                    if workDir.isEmpty {
                        pidsNeedingCwd.append((found.count - 1, pid))
                    }
                }
            } else if execBase == "opencode" {
                let key = "tty-\(tty)"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                let idx = found.count + 1
                found.append(
                    RealTerminalWindow(
                        id: "Terminal:\(tty):\(idx)",
                        appKind: .appleTerminal,
                        windowId: tty,
                        tabIndex: idx,
                        title: "opencode (\(tty))",
                        workingDirectory: "",
                        isActiveTab: idx == 1,
                        isFrontmostApp: isAnyTermFrontmost && idx == 1
                    )
                )
                pidsNeedingCwd.append((found.count - 1, pid))
            }
        }

        // 对缺少 -c 参数的直连 opencode 进程，用 lsof -a -d cwd 补齐真实工作目录
        for item in pidsNeedingCwd {
            if let lsofOut = runSubprocess(executable: "/usr/sbin/lsof", arguments: ["-a", "-p", item.pid, "-d", "cwd", "-Fn"]) {
                for l in lsofOut.components(separatedBy: .newlines) where l.hasPrefix("n/") {
                    let cwd = String(l.dropFirst())
                    let old = found[item.idx]
                    let folder = (cwd as NSString).lastPathComponent
                    found[item.idx] = RealTerminalWindow(
                        id: old.id,
                        appKind: old.appKind,
                        windowId: old.windowId,
                        tabIndex: old.tabIndex,
                        title: folder.isEmpty ? old.title : "\(old.windowId) · \(folder)",
                        workingDirectory: cwd,
                        isActiveTab: old.isActiveTab,
                        isFrontmostApp: old.isFrontmostApp
                    )
                    break
                }
            }
        }

        return found
    }

    @discardableResult
    private static func runAppleScript(_ source: String) -> String? {
        return runSubprocess(executable: "/usr/bin/osascript", arguments: ["-e", source])
    }

    private static func runSubprocess(executable: String, arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            return nil
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
