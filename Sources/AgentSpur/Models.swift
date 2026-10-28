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
        case .completed: return "空闲"
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

    /// 实时运行态聚合优先级：任何正在活跃执行的任务（等你确认 > 正在工作 > 正在思考）绝对优先于已停止的历史报错子任务
    var activeFirstRank: Int {
        switch self {
        case .confirm:   return 50
        case .working:   return 40
        case .thinking:  return 30
        case .error:     return 20
        case .completed: return 10
        }
    }

    var isActiveRunning: Bool {
        self == .thinking || self == .working || self == .confirm
    }

    var accentColor: NSColor {
        switch self {
        case .thinking:  return NSColor(srgbRed: 0.01, green: 0.52, blue: 0.78, alpha: 1.0) // Sky 600
        case .working:   return NSColor(srgbRed: 0.02, green: 0.44, blue: 0.72, alpha: 1.0) // Ocean 700
        case .confirm:   return NSColor(srgbRed: 0.85, green: 0.47, blue: 0.02, alpha: 1.0) // Amber 600
        case .completed: return NSColor(srgbRed: 0.06, green: 0.62, blue: 0.40, alpha: 1.0) // Emerald 600
        case .error:     return NSColor(srgbRed: 0.86, green: 0.15, blue: 0.15, alpha: 1.0) // Rose 600
        }
    }

    var pillBackgroundColor: NSColor {
        switch self {
        case .thinking, .working:
            return NSColor(srgbRed: 0.93, green: 0.97, blue: 1.00, alpha: 1.0)
        case .confirm:
            return NSColor(srgbRed: 1.00, green: 0.97, blue: 0.91, alpha: 1.0)
        case .completed:
            return NSColor(srgbRed: 0.94, green: 0.98, blue: 0.96, alpha: 1.0)
        case .error:
            return NSColor(srgbRed: 1.00, green: 0.94, blue: 0.94, alpha: 1.0)
        }
    }

    var pillBorderColor: NSColor {
        switch self {
        case .thinking, .working:
            return NSColor(srgbRed: 0.73, green: 0.90, blue: 0.99, alpha: 0.9)
        case .confirm:
            return NSColor(srgbRed: 0.98, green: 0.82, blue: 0.55, alpha: 0.9)
        case .completed:
            return NSColor(srgbRed: 0.72, green: 0.92, blue: 0.82, alpha: 0.9)
        case .error:
            return NSColor(srgbRed: 0.98, green: 0.74, blue: 0.74, alpha: 0.9)
        }
    }
}

// MARK: - Notification Event

struct AgentNotificationEvent: Equatable {
    enum Kind: Equatable {
        case completed
        case confirmNeeded
        case errorOccurred
    }
    let kind: Kind
    let taskTitle: String
}

// MARK: - Multi API-Key Profile & O(1) Pre-Aggregated Scoped Telemetry

struct APIKeyProfile: Codable, Equatable {
    static let allKeysId = "__ALL__"

    let id: String
    var name: String              // 如 "DeepSeek 官方"、"默认主Key"
    var rawApiKey: String         // 完整 sk-... 用于查询实时余额（仅存本机内存/偏好）
    var maskedKey: String         // 如 "sk-***01"
    var directoryKeyword: String  // 可选：工作目录或通道匹配词
    var providerId: String        // 关联 opencode.db message.data.$.providerID
    var autoSource: String?       // 如 "opencode.db"、"auth.json"、"opencode.json"

    init(
        id: String,
        name: String,
        rawApiKey: String,
        maskedKey: String,
        directoryKeyword: String,
        providerId: String = "",
        autoSource: String? = nil
    ) {
        self.id = id
        self.name = name
        self.rawApiKey = rawApiKey
        self.maskedKey = maskedKey
        self.directoryKeyword = directoryKeyword
        self.providerId = providerId
        self.autoSource = autoSource
    }

    enum CodingKeys: String, CodingKey {
        case id, name, rawApiKey, maskedKey, directoryKeyword, providerId, autoSource
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.rawApiKey = (try? c.decodeIfPresent(String.self, forKey: .rawApiKey)) ?? ""
        self.maskedKey = (try? c.decodeIfPresent(String.self, forKey: .maskedKey)) ?? ""
        self.directoryKeyword = (try? c.decodeIfPresent(String.self, forKey: .directoryKeyword)) ?? ""
        self.providerId = (try? c.decodeIfPresent(String.self, forKey: .providerId)) ?? ""
        self.autoSource = try? c.decodeIfPresent(String.self, forKey: .autoSource)
    }

    var isAutoDiscovered: Bool {
        autoSource != nil
    }

    var displayTitle: String {
        if maskedKey.isEmpty {
            return name
        }
        if name.contains(maskedKey) {
            return name
        }
        return "\(name) (\(maskedKey))"
    }

    static func makeMasked(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return trimmed }
        let prefix = String(trimmed.prefix(3))
        let suffix = String(trimmed.suffix(2))
        return "\(prefix)***\(suffix)"
    }
}

struct KeyScopedTelemetry: Equatable {
    let keyId: String
    let title: String
    let billing: BillingTelemetrySummary
    let todayHourlySeries: [TodayHourlyPoint]
    let masters: [MasterSessionItem]
}

// MARK: - Real Discovered Console Window / Tab / tmux Pane (Zero Fake Data)

enum RealConsoleAppKind: String, Codable, Equatable {
    case appleTerminal = "Terminal"
    case iterm2        = "iTerm2"
    case tmux          = "tmux"
}

struct RealTerminalWindow: Equatable {
    let id: String                // 唯一标识，如 "Terminal:1024:1" 或 "tmux:oc-opencode-master:1"
    let appKind: RealConsoleAppKind
    let windowId: String
    let tabIndex: Int             // 1-based 真实标签页序号
    let title: String             // 真实窗口/Tab标题
    let workingDirectory: String  // 真实工作目录
    let isActiveTab: Bool
    let isFrontmostApp: Bool

    var popupMenuTitle: String {
        let cleanTitle = title.count > 34 ? String(title.prefix(34)) + "…" : title
        return "\(appKind.rawValue) #\(tabIndex) · \(cleanTitle)"
    }

    func indexedMenuTitle(index: Int) -> String {
        let dirName = (workingDirectory as NSString).lastPathComponent
        let baseTitle: String
        if !dirName.isEmpty && !title.lowercased().contains(dirName.lowercased()) {
            baseTitle = "\(dirName) · \(title)"
        } else {
            baseTitle = title
        }
        let cleanTitle = baseTitle.count > 30 ? String(baseTitle.prefix(30)) + "…" : baseTitle
        let tabTag = tabIndex > 1 ? "#\(tabIndex)" : ""
        return String(format: "%02d · %@%@ · %@", index, appKind.rawValue, tabTag, cleanTitle)
    }

    var shortTargetSummary: String {
        let dirName = (workingDirectory as NSString).lastPathComponent
        if !dirName.isEmpty {
            let shortDir = dirName.count > 10 ? String(dirName.prefix(10)) + "…" : dirName
            return "\(appKind.rawValue)·\(shortDir)"
        }
        let shortTitle = title.count > 10 ? String(title.prefix(10)) + "…" : title
        return "\(appKind.rawValue)·\(shortTitle)"
    }

    var shortBadge: String {
        if appKind == .tmux {
            let shortWin = windowId.count > 12 ? String(windowId.prefix(12)) : windowId
            return "tmux·\(shortWin)"
        }
        return "\(appKind.rawValue)#\(tabIndex)"
    }
}

// MARK: - Currency & DeepSeek Pricing Models

enum CurrencyDisplayMode: String, CaseIterable {
    case cny = "CNY"
    case usd = "USD"

    var symbol: String {
        self == .cny ? "¥" : "$"
    }

    var toggleButtonTitle: String {
        switch self {
        case .cny: return "¥ CNY"
        case .usd: return "$ USD"
        }
    }

    var next: CurrencyDisplayMode {
        self == .cny ? .usd : .cny
    }
}

enum MenuBarDisplayMode: String, Codable, CaseIterable {
    case iconOnly      = "iconOnly"      // 仅灵动图标 (22pt 紧凑宽度，默认开启，防切屏被 Chrome/IDE 长菜单或刘海屏折叠隐藏)
    case compactAmount = "compactAmount" // 图标 + 简短金额 (如 ¥46)
    case fullStatus    = "fullStatus"    // 图标 + 状态与完整金额 (适合外接宽屏显示器)

    var settingsTitle: String {
        switch self {
        case .iconOnly:      return "菜单栏：仅灵动图标（防切屏隐藏）"
        case .compactAmount: return "菜单栏：图标 + 简短金额"
        case .fullStatus:    return "菜单栏：图标 + 状态与金额"
        }
    }
}

enum FloatingBadgeMode: String, Codable, CaseIterable {
    case autoWhenOccluded = "autoWhenOccluded" // 默认：检测到菜单栏被刘海屏/长菜单挤压隐藏或进入全屏空间时，自动弹出右上角微胶囊
    case always           = "always"           // 始终显示跨屏常驻微胶囊
    case off              = "off"              // 关闭桌面微胶囊（仅使用系统菜单栏图标）

    var settingsTitle: String {
        switch self {
        case .autoWhenOccluded: return "刘海遮挡/全屏时自动悬浮胶囊"
        case .always:           return "始终显示跨屏常驻悬浮胶囊"
        case .off:              return "关闭桌面悬浮胶囊（仅菜单栏）"
        }
    }
}

enum BeijingPriceWindow {
    case offPeak // 闲时 50% 折扣 (夜间 18:00-09:00、午休 12:00-14:00、周末及中国法定节假日全天)
    case peak    // 忙时原价 (工作日 09:00-12:00, 14:00-18:00 UTC+8)

    var badgeText: String {
        switch self {
        case .offPeak: return "闲时 5 折"
        case .peak:    return "忙时原价"
        }
    }
}

enum DeepSeekModelTier {
    case flash  // deepseek-flash (DeepSeek-V4.1-Flash-1017) & v4.1-flash / v4-flash aliases
    case v4Pro  // deepseek-v4-pro (DeepSeek-V4-Pro-0813)
    case other(String)

    var canonicalModelId: String {
        switch self {
        case .flash: return "deepseek-flash"
        case .v4Pro: return "deepseek-v4-pro"
        case .other(let raw): return raw.isEmpty ? "deepseek-flash" : raw
        }
    }

    var specSummary: String {
        switch self {
        case .flash:
            return "V4.1-Flash · 1M上下文 · 并发2500"
        case .v4Pro:
            return "V4-Pro · 1M上下文 · 并发500"
        case .other(let raw):
            return "\(raw) · 按实时汇率折算"
        }
    }
}

/// 今日使用情况精算与 Cache 深度透视汇总（100% 扫描今日全量消息 + 自动去重思维链不双计）
struct BillingTelemetrySummary: Equatable {
    let dateLabel: String             // 如 "今日 10/28"
    let dominantModelId: String
    let dominantModelSpec: String
    let inputCacheHitTokens: Int64    // amount.csv -> input_cache_hit_tokens
    let inputCacheMissTokens: Int64   // amount.csv -> input_cache_miss_tokens (含新建缓存)
    let cacheWriteTokens: Int64       // opencode.db -> tokens.cache.write (冷启动写入细分)
    let outputTokens: Int64           // amount.csv -> output_tokens (精确对齐 completion_tokens，不重复叠加 reasoning)
    let reasoningTokens: Int64        // 其中思维链 tokens.reasoning 占比明细
    let requestCount: Int             // 今日总请求次数
    let offPeakRequestCount: Int      // 今日闲时 5 折请求数
    let spurCostCny: Double           // 今日 Spur 精算人民币总花费
    let peakCostCny: Double           // 今日忙时时段产生的实际花费 (CNY)
    let offPeakCostCny: Double        // 今日闲时时段产生的实际花费 (CNY)
    let cacheHitCostCny: Double       // 缓存命中部分实际花费 (CNY)
    let cacheMissCostCny: Double      // 缓存未命中部分实际花费 (CNY)
    let outputCostCny: Double         // 输出(含推理)部分实际花费 (CNY)
    let cacheSavedCny: Double         // 因上下文缓存命中直接省下的人民币净额
    let offPeakSavedCny: Double       // 因闲时 5 折时段直接省下的人民币净额
    let opencodeRawUsd: Double        // 今日 opencode 静态单价记录的原始美元估值

    var totalInputTokens: Int64 {
        inputCacheHitTokens + inputCacheMissTokens
    }

    var peakRequestCount: Int {
        max(0, requestCount - offPeakRequestCount)
    }

    var cacheHitRatePercent: Double {
        let totalIn = totalInputTokens
        guard totalIn > 0 else { return 0.0 }
        return (Double(inputCacheHitTokens) / Double(totalIn)) * 100.0
    }

    var cacheMissRatePercent: Double {
        let totalIn = totalInputTokens
        guard totalIn > 0 else { return 0.0 }
        return max(0.0, 100.0 - cacheHitRatePercent)
    }

    var offPeakRatePercent: Double {
        guard requestCount > 0 else { return 0.0 }
        return (Double(offPeakRequestCount) / Double(requestCount)) * 100.0
    }

    var avgCostPerRequestCny: Double {
        guard requestCount > 0 else { return 0.0 }
        return spurCostCny / Double(requestCount)
    }

    static func empty(dateLabel: String, tier: DeepSeekModelTier) -> BillingTelemetrySummary {
        BillingTelemetrySummary(
            dateLabel: dateLabel,
            dominantModelId: tier.canonicalModelId,
            dominantModelSpec: tier.specSummary,
            inputCacheHitTokens: 0,
            inputCacheMissTokens: 0,
            cacheWriteTokens: 0,
            outputTokens: 0,
            reasoningTokens: 0,
            requestCount: 0,
            offPeakRequestCount: 0,
            spurCostCny: 0.0,
            peakCostCny: 0.0,
            offPeakCostCny: 0.0,
            cacheHitCostCny: 0.0,
            cacheMissCostCny: 0.0,
            outputCostCny: 0.0,
            cacheSavedCny: 0.0,
            offPeakSavedCny: 0.0,
            opencodeRawUsd: 0.0
        )
    }
}

/// 导入 DeepSeek 官方导出的 amount-*.csv / cost-*.csv 对账快照
struct OfficialCSVReconciliation: Codable, Equatable {
    let importedFileNames: [String]
    let modelName: String
    let apiKeyName: String
    let maskedApiKey: String
    let walletType: String            // cost.csv -> Paid / Granted
    let currency: String              // cost.csv -> CNY / USD
    let inputCacheHitTokens: Int64
    let inputCacheMissTokens: Int64
    let outputTokens: Int64
    let requestCount: Int
    let unitHitPriceCny: Double?
    let unitMissPriceCny: Double?
    let unitOutputPriceCny: Double?
    let totalCostInOriginalCurrency: Double
    let timeRangeLabel: String

    var totalInputTokens: Int64 {
        inputCacheHitTokens + inputCacheMissTokens
    }

    var cacheHitRatePercent: Double {
        let totalIn = totalInputTokens
        guard totalIn > 0 else { return 0.0 }
        return (Double(inputCacheHitTokens) / Double(totalIn)) * 100.0
    }

    var estimatedCacheSavedCny: Double {
        let hitP = unitHitPriceCny ?? 0.00000002
        let missP = unitMissPriceCny ?? 0.000001
        guard missP > hitP else { return 0.0 }
        return Double(max(0, inputCacheHitTokens)) * (missP - hitP)
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

    var badgeEmoji: String {
        switch self {
        case .droplet:     return "💧"
        case .glyph:       return "◎"
        case .whale:       return "🐳"
        case .neko:        return "🐱"
        case .kitsune:     return "🦊"
        case .customPixel: return "👾"
        }
    }
}

struct DeepSeekRolePack: Codable, Equatable {
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

    var menuTitle: String {
        "\(archetype.badgeEmoji) \(name)"
    }

    static let builtInPacks: [DeepSeekRolePack] = [
        DeepSeekRolePack(
            id: "pack-gin-droplet",
            name: "Gin · 灵动微光",
            author: "AgentSpur",
            version: "1.0.0",
            deepseekModel: "deepseek-flash",
            roleDescription: "极简冰瓷流体水滴，15 FPS 五状态灵动反馈",
            archetype: .droplet,
            primaryColor: "#0284C7",
            secondaryColor: "#38BDF8",
            customBaseSprite: nil
        ),
        DeepSeekRolePack(
            id: "pack-deepseek-whale",
            name: "深海小鲸",
            author: "DeepSeek Community",
            version: "1.2.0",
            deepseekModel: "deepseek-v4-pro",
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
            deepseekModel: "deepseek-flash",
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
            deepseekModel: "deepseek-v4-pro",
            roleDescription: "几何折纸灵狐，双耳随确认灵动反馈",
            archetype: .kitsune,
            primaryColor: "#EA580C",
            secondaryColor: "#0284C7",
            customBaseSprite: nil
        ),
        DeepSeekRolePack(
            id: "pack-appkit-glyph",
            name: "AppKit 极简线条",
            author: "macOS HIG",
            version: "1.0.0",
            deepseekModel: "deepseek-flash",
            roleDescription: "纯净几何线条，零视觉负担",
            archetype: .glyph,
            primaryColor: "#1E293B",
            secondaryColor: "#0EA5E9",
            customBaseSprite: nil
        )
    ]
}

// MARK: - Today Session & Hourly Chart Models (Strictly from opencode.db + Real Terminal)

struct SubTaskItem: Equatable {
    let id: String
    let parentId: String
    let title: String
    let roleLabel: String
    let directory: String
    let apiKeyBucket: String
    var state: AgentRunState
    var stateEnteredAtMs: Int64
    var completedDurationSec: Int64?
    var matchedWindow: RealTerminalWindow?
    var dbRecordRef: String
    var spurCostCny: Double
    var opencodeRawUsd: Double
    var requestCount: Int
    var inputCacheHitTokens: Int64
    var inputCacheMissTokens: Int64
    var outputTokens: Int64
    var cacheSavedCny: Double
    var cacheHitPercent: Double

    var consoleBadgeText: String {
        if let w = matchedWindow {
            return w.shortBadge
        }
        let base = (directory as NSString).lastPathComponent
        return base.isEmpty ? "后台会话" : String(base.prefix(13))
    }
}

struct MasterSessionItem: Equatable {
    let id: String
    let title: String
    let modelName: String
    let directory: String
    let apiKeyBucket: String
    var state: AgentRunState
    var stateEnteredAtMs: Int64
    var completedDurationSec: Int64?
    var matchedWindow: RealTerminalWindow?
    var dbRecordRef: String
    var ownCostCny: Double            // 主会话自身直接消息精算开销（对应 OpenCode 右侧栏单会话口径）
    var ownOpenCodeUsd: Double        // 主会话自身 OpenCode 原始记录美元数（对应 TUI 右侧 "$0.04 spent"）
    var spurCostCny: Double           // 含全部子任务汇总精算总开销
    var requestCount: Int
    var inputCacheHitTokens: Int64
    var inputCacheMissTokens: Int64
    var outputTokens: Int64
    var cacheSavedCny: Double
    var cacheHitPercent: Double
    var subTasks: [SubTaskItem]

    var consoleBadgeText: String {
        if let w = matchedWindow {
            return w.shortBadge
        }
        let base = (directory as NSString).lastPathComponent
        return base.isEmpty ? "本地会话" : String(base.prefix(13))
    }
}

/// 今日 24 小时分时使用趋势点（由单次今日 message 查询在内存聚合，零额外 SQL 开销）
struct TodayHourlyPoint: Equatable {
    let hour: Int                  // 0...23
    let hourLabel: String          // "00", "06", "12", "18"
    let requestCount: Int          // 该小时请求次数
    let costCny: Double            // 该小时精算人民币花费
    let cacheHitPercent: Double    // 该小时缓存命中率 (0...100)
    let isPeakHour: Bool           // 该小时是否属于北京时间工作日忙时
    let isCurrentHour: Bool
}

struct QuotaSnapshot: Equatable {
    var apiTotalBalance: Double?      // 若配置了或自动提取到 sk-...，返回官方实时余额数值
    var apiCurrency: String           // "CNY" 或 "USD"
    var walletBreakdownLabel: String  // 如 "Paid ¥2785.36" 或 "Paid"
    var balanceSourceLabel: String = "" // 如 "api.deepseek.com · DeepSeek 官方 (sk-***xx)"
    var usdToCnyRate: Double          // 线上实时 USD/CNY 汇率
    var fxSourceLabel: String         // 如 "实时汇率" / "缓存汇率"
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
            return String(format: "%dm%02ds", m, s)
        }
        let h = sec / 3600
        let m = (sec % 3600) / 60
        return String(format: "%dh%02dm", h, m)
    }

    static func liveStateTimerLabel(state: AgentRunState, enteredAtMs: Int64, nowMs: Int64) -> String {
        let elapsedSec = max(0, (nowMs - enteredAtMs) / 1000)
        return "\(state.livePrefix) \(formatCompactSeconds(elapsedSec))"
    }

    static func compactTimerOnly(enteredAtMs: Int64, nowMs: Int64) -> String {
        let elapsedSec = max(0, (nowMs - enteredAtMs) / 1000)
        return formatCompactSeconds(elapsedSec)
    }

    static func currentHHMM() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: Date())
    }

    static func todayShortLabel() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd"
        return "今日 \(fmt.string(from: Date()))"
    }

    static func formatTokenCount(_ count: Int64) -> String {
        if count >= 1_000_000_000 {
            return String(format: "%.2fB", Double(count) / 1_000_000_000.0)
        }
        if count >= 1_000_000 {
            return String(format: "%.2fM", Double(count) / 1_000_000.0)
        }
        if count >= 10_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    static func formatIntWithCommas(_ value: Int) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: value)) ?? "\(value)"
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
