import AppKit
import Foundation

// MARK: - 5 Real-Time Agent States

enum AgentRunState: String, Codable, CaseIterable {
    case thinking  = "thinking"
    case working   = "working"
    case confirm   = "confirm"
    case completed = "completed"
    case error     = "error"

    var label: String {
        switch self {
        case .thinking:  return "思考"
        case .working:   return "工作"
        case .confirm:   return "等你确认"
        case .completed: return "完成"
        case .error:     return "出错"
        }
    }

    var livePrefix: String {
        switch self {
        case .thinking:  return "正在思考"
        case .working:   return "正在工作"
        case .confirm:   return "等你确认"
        case .completed: return "已完成"
        case .error:     return "已出错"
        }
    }

    var priority: Int {
        switch self {
        case .error:     return 5
        case .confirm:   return 4
        case .working:   return 3
        case .thinking:  return 2
        case .completed: return 1
        }
    }

    var accentColor: NSColor {
        switch self {
        case .thinking:  return NSColor(srgbRed: 0.01, green: 0.52, blue: 0.78, alpha: 1.0) // Sky 600
        case .working:   return NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0) // Slate 900
        case .confirm:   return NSColor(srgbRed: 0.85, green: 0.47, blue: 0.02, alpha: 1.0) // Amber 600
        case .completed: return NSColor(srgbRed: 0.09, green: 0.64, blue: 0.29, alpha: 1.0) // Emerald 600
        case .error:     return NSColor(srgbRed: 0.86, green: 0.15, blue: 0.15, alpha: 1.0) // Rose 600
        }
    }
}

// MARK: - Target Terminal & Auto-Focus Filter

enum TargetTerminalApp: String, Codable {
    case opencodeTUI = "opencode TUI"
    case iterm2      = "iTerm2"
}

enum AutoFocusWindowTarget: String, CaseIterable {
    case opencodeTUI = "opencode TUI 窗口"
    case itermAll    = "iTerm2 全部窗口"
    case itermTab1   = "iTerm2 · Tab 1"
    case itermTab2   = "iTerm2 · Tab 2"
    case itermTab3   = "iTerm2 · Tab 3"
    case itermTab4   = "iTerm2 · Tab 4"

    func matches(task: SubTaskItem, frontmostHint: FrontmostTerminalHint?) -> Bool {
        switch self {
        case .opencodeTUI:
            if let hint = frontmostHint, hint.isTerminalActive {
                return task.targetApp == .opencodeTUI || hint.titleContainsOpencode
            }
            return task.targetApp == .opencodeTUI
        case .itermAll:
            return task.targetApp == .iterm2
        case .itermTab1:
            return task.targetApp == .iterm2 && task.itermTabIndex == 0
        case .itermTab2:
            return task.targetApp == .iterm2 && task.itermTabIndex == 1
        case .itermTab3:
            return task.targetApp == .iterm2 && task.itermTabIndex == 2
        case .itermTab4:
            return task.targetApp == .iterm2 && task.itermTabIndex == 3
        }
    }
}

struct FrontmostTerminalHint {
    let appName: String
    let windowTitle: String
    let activeTabIndex: Int?

    var isTerminalActive: Bool {
        appName == "iTerm2" || appName == "Terminal" || appName.lowercased().contains("opencode")
    }

    var titleContainsOpencode: Bool {
        windowTitle.lowercased().contains("opencode")
    }
}

// MARK: - DeepSeek Character Pack

enum CharacterArchetype: String, Codable {
    case droplet      = "droplet"
    case glyph        = "glyph"
    case whale        = "whale"
    case neko         = "neko"
    case kitsune      = "kitsune"
    case customPixel  = "custom_pixel"
}

struct DeepSeekRolePack: Codable {
    let id: String
    let name: String
    let author: String?
    let version: String?
    let deepseekModel: String
    let roleDescription: String?
    let archetype: CharacterArchetype
    let primaryColor: String
    let secondaryColor: String
    let customBaseSprite: [String]?

    static let builtInPacks: [DeepSeekRolePack] = [
        DeepSeekRolePack(
            id: "pack-gin-droplet",
            name: "Gin · 灵动微光",
            author: "AgentSpur",
            version: "1.0.0",
            deepseekModel: "deepseek/deepseek-reasoner",
            roleDescription: "极简冰瓷流体水滴，15 FPS 五状态灵动反馈",
            archetype: .droplet,
            primaryColor: "#0284C7",
            secondaryColor: "#38BDF8",
            customBaseSprite: nil
        ),
        DeepSeekRolePack(
            id: "pack-appkit-glyph",
            name: "AppKit 极简线条",
            author: "macOS HIG",
            version: "1.0.0",
            deepseekModel: "deepseek/deepseek-chat",
            roleDescription: "纯净几何线条，零视觉负担",
            archetype: .glyph,
            primaryColor: "#1E293B",
            secondaryColor: "#0EA5E9",
            customBaseSprite: nil
        ),
        DeepSeekRolePack(
            id: "pack-deepseek-whale",
            name: "深海小鲸",
            author: "DeepSeek Community",
            version: "1.2.0",
            deepseekModel: "deepseek/deepseek-reasoner",
            roleDescription: "微缩蓝鲸角色包，声呐气泡与尾鳍节拍",
            archetype: .whale,
            primaryColor: "#0284C7",
            secondaryColor: "#38BDF8",
            customBaseSprite: nil
        ),
        DeepSeekRolePack(
            id: "pack-deepseek-neko",
            name: "晴空像素猫",
            author: "PixelCraft",
            version: "1.4.0",
            deepseekModel: "deepseek/deepseek-chat",
            roleDescription: "轻量菜单栏像素猫，工作双爪轻敲",
            archetype: .neko,
            primaryColor: "#334155",
            secondaryColor: "#F59E0B",
            customBaseSprite: nil
        ),
        DeepSeekRolePack(
            id: "pack-deepseek-kitsune",
            name: "折纸灵狐",
            author: "Kitsune Lab",
            version: "1.0.5",
            deepseekModel: "deepseek/deepseek-reasoner",
            roleDescription: "几何折纸灵狐，双耳随确认灵动反馈",
            archetype: .kitsune,
            primaryColor: "#EA580C",
            secondaryColor: "#0284C7",
            customBaseSprite: nil
        )
    ]
}

// MARK: - Session & Analytics Models (Strictly from opencode.db)

struct SubTaskItem {
    let id: String
    let parentId: String
    let title: String
    let roleLabel: String
    let directory: String
    var state: AgentRunState
    var stateEnteredAtMs: Int64
    var completedDurationSec: Int64?
    var targetApp: TargetTerminalApp
    var itermTabIndex: Int
    var dbRecordRef: String
}

struct MasterSessionItem {
    let id: String
    let title: String
    let modelName: String
    let directory: String
    var state: AgentRunState
    var stateEnteredAtMs: Int64
    var completedDurationSec: Int64?
    var targetApp: TargetTerminalApp
    var itermTabIndex: Int
    var dbRecordRef: String
    var subTasks: [SubTaskItem]
}

struct DailyEfficiencyPoint {
    let dayLabel: String
    let dateShort: String
    let tasksPerHour: Double
    let avgSeconds: Double
    let completedCount: Int
    let isToday: Bool
}

struct QuotaSnapshot {
    var displayBalance: String
    var resetTimeLabel: String
    var lastRefreshedHHMM: String
}

enum SessionGroupFilter: Int {
    case all = 0
    case pending = 1
    case running = 2
    case completed = 3
}

// MARK: - Formatting Helpers

enum TimeFormatters {
    static func formatCompactSeconds(_ rawSeconds: Int64) -> String {
        let sec = max(0, rawSeconds)
        if sec < 60 {
            return "\(sec)s"
        }
        if sec < 3600 {
            let m = sec / 60
            let s = sec % 60
            return String(format: "%dm %02ds", m, s)
        }
        let h = sec / 3600
        let m = (sec % 3600) / 60
        return String(format: "%dh %02dm", h, m)
    }

    static func liveStateTimerLabel(state: AgentRunState, enteredAtMs: Int64, nowMs: Int64) -> String {
        let elapsedSec = max(0, (nowMs - enteredAtMs) / 1000)
        return "\(state.livePrefix) \(formatCompactSeconds(elapsedSec))"
    }

    static func currentHHMM() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: Date())
    }
}

extension NSColor {
    static func fromHex(_ hex: String, fallback: NSColor = .systemBlue) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let val = UInt64(cleaned, radix: 16) else {
            return fallback
        }
        let r = CGFloat((val >> 16) & 0xFF) / 255.0
        let g = CGFloat((val >> 8) & 0xFF) / 255.0
        let b = CGFloat(val & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
