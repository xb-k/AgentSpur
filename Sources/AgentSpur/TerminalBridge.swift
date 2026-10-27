import AppKit
import Foundation

enum TerminalBridge {
    /// 点击会话或子任务时，跳回对应的 opencode TUI 或 iTerm2 标签页（不强行重排桌面窗口）
    static func jumpToSession(targetApp: TargetTerminalApp, directory: String, itermTabIndex: Int) {
        let escapedDir = directory.replacingOccurrences(of: "\"", with: "\\\"")
        let oneBasedTab = max(1, itermTabIndex + 1)

        let scriptSource = """
        tell application "System Events"
            set procNames to name of every process
        end tell

        if procNames contains "iTerm2" then
            tell application "iTerm2"
                activate
                if (count of windows) > 0 then
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if ("\(escapedDir)" is not "" and name of s contains "\(escapedDir)") or (name of s contains "opencode") then
                                    select t
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                    tell current window
                        if (count of tabs) >= \(oneBasedTab) then
                            select tab \(oneBasedTab)
                        end if
                    end tell
                end if
            end tell
        else if procNames contains "Terminal" then
            tell application "Terminal"
                activate
            end tell
        end if
        """

        if let script = NSAppleScript(source: scriptSource) {
            var err: NSDictionary?
            script.executeAndReturnError(&err)
        }
    }

    /// 检测当前前台终端窗口与活跃 iTerm2 标签页，供「终端自动聚焦模式」使用
    static func inspectFrontmostTerminal() -> FrontmostTerminalHint? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName else {
            return nil
        }

        if appName == "iTerm2" {
            let scriptSource = """
            tell application "iTerm2"
                if (count of windows) is 0 then return ""
                tell current window
                    set tabIdx to 1
                    repeat with i from 1 to (count of tabs)
                        if item i of tabs is current tab then
                            set tabIdx to i
                            exit repeat
                        end if
                    end repeat
                    set sessName to name of current session
                    return (tabIdx as string) & "|" & sessName
                end tell
            end tell
            """
            if let script = NSAppleScript(source: scriptSource) {
                var err: NSDictionary?
                let out = script.executeAndReturnError(&err)
                if let raw = out.stringValue, !raw.isEmpty {
                    let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
                    let idx = parts.first.flatMap { Int($0) }.map { max(0, $0 - 1) }
                    let title = parts.count > 1 ? parts[1] : ""
                    return FrontmostTerminalHint(appName: appName, windowTitle: title, activeTabIndex: idx)
                }
            }
        }

        return FrontmostTerminalHint(appName: appName, windowTitle: appName, activeTabIndex: nil)
    }
}
