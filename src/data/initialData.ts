import {
  AgentStatus,
  CharacterPack,
  MasterSession,
  QuotaState,
  TargetApp,
  WeeklyEfficiencyPoint,
} from '../types/agent';
import { OPENCODE_DB_PATH } from '../utils/opencodeDb';

const BOOT_TS = Date.now();

export const STATUS_META: Record<
  AgentStatus,
  {
    label: string;
    shortVerb: string;
    colorHex: string;
    textClass: string;
    frameNote: string;
  }
> = {
  [AgentStatus.Thinking]: {
    label: '思考',
    shortVerb: '推理中',
    colorHex: '#0284C7',
    textClass: 'text-sky-600',
    frameNote: '15 FPS · 呼吸涟漪',
  },
  [AgentStatus.Working]: {
    label: '工作',
    shortVerb: '执行中',
    colorHex: '#0F172A',
    textClass: 'text-slate-900',
    frameNote: '15 FPS · 轻快律动',
  },
  [AgentStatus.Confirm]: {
    label: '等你确认',
    shortVerb: '待确认',
    colorHex: '#D97706',
    textClass: 'text-amber-600',
    frameNote: '15 FPS · 柔光唤起',
  },
  [AgentStatus.Completed]: {
    label: '完成',
    shortVerb: '已就绪',
    colorHex: '#16A34A',
    textClass: 'text-emerald-600',
    frameNote: '15 FPS · 轻盈收束',
  },
  [AgentStatus.Error]: {
    label: '出错',
    shortVerb: '已中断',
    colorHex: '#DC2626',
    textClass: 'text-rose-600',
    frameNote: '15 FPS · 瞬态震颤',
  },
};

export const BUILTIN_CHARACTER_PACKS: CharacterPack[] = [
  {
    id: 'pack-gin-droplet',
    name: 'Gin · 灵动微光',
    author: 'Minimalist Lab',
    version: '1.0.0',
    deepseekModel: 'deepseek/deepseek-reasoner',
    roleDescription: '极简流体水滴精灵，以轻盈形变与微光眼神演绎 15 FPS 五状态。',
    archetype: 'droplet',
    primaryColor: '#0F172A',
    secondaryColor: '#0EA5E9',
    isBuiltIn: true,
  },
  {
    id: 'pack-appkit-glyph',
    name: 'AppKit 极简线条',
    author: 'macOS HIG',
    version: '2.0.0',
    deepseekModel: 'deepseek/deepseek-chat',
    roleDescription: '遵循 Apple NSImage.isTemplate 纯净几何线条，零视觉负担。',
    archetype: 'glyph',
    primaryColor: '#18181B',
    secondaryColor: '#52525B',
    isBuiltIn: true,
  },
  {
    id: 'pack-deepseek-whale',
    name: '深海小鲸',
    author: 'DeepSeek Community',
    version: '1.2.0',
    deepseekModel: 'deepseek/deepseek-reasoner',
    roleDescription: '微缩蓝鲸角色包，以声呐气泡与尾鳍节拍呈现 15 FPS 状态。',
    archetype: 'whale',
    primaryColor: '#0284C7',
    secondaryColor: '#38BDF8',
    isBuiltIn: true,
  },
  {
    id: 'pack-deepseek-neko',
    name: '晴空像素猫',
    author: 'PixelCraft',
    version: '1.4.2',
    deepseekModel: 'deepseek/deepseek-chat',
    roleDescription: '菜单栏轻量像素猫，思考凝视气泡，工作双爪轻敲。',
    archetype: 'neko',
    primaryColor: '#1E293B',
    secondaryColor: '#F59E0B',
    isBuiltIn: true,
  },
  {
    id: 'pack-deepseek-kitsune',
    name: '折纸灵狐',
    author: 'Kitsune Lab',
    version: '1.0.5',
    deepseekModel: 'deepseek/deepseek-reasoner',
    roleDescription: '极简几何折纸狐，双耳随确认与异常状态灵动反馈。',
    archetype: 'kitsune',
    primaryColor: '#EA580C',
    secondaryColor: '#0284C7',
    isBuiltIn: true,
  },
];

export const SAMPLE_CUSTOM_PACK_JSON = {
  id: 'custom-deepseek-gin-sprite',
  name: '自制微星精灵',
  author: 'Local Mac User',
  version: '1.0.0',
  deepseekModel: 'deepseek/deepseek-reasoner',
  roleDescription: '本地 JSON 导入的极简 12x12 点阵角色包。',
  archetype: 'custom_pixel',
  primaryColor: '#0F172A',
  secondaryColor: '#0EA5E9',
  customBaseSprite: [
    '....####....',
    '..########..',
    '.##########.',
    '.###+##+###.',
    '.###+##+###.',
    '.##########.',
    '..########..',
    '...######...',
    '....####....',
    '............',
    '............',
    '............',
  ],
};

export const INITIAL_QUOTA: QuotaState = {
  remainingUsd: 24.85,
  totalUsd: 35.0,
  resetTimeLabel: '04:00重置',
  resetCountdown: '02h 46m',
  lastRefreshedAt: '01:14',
};

export const INITIAL_SESSIONS: MasterSession[] = [
  {
    id: 'master-confirm-01',
    title: '重构 Gin 路由中间件鉴权与限流策略',
    engine: 'opencode',
    modelName: 'deepseek/deepseek-reasoner',
    status: AgentStatus.Confirm,
    stateEnteredAt: BOOT_TS - 7_000,
    dbRecordRef: "permission(per_8f2a) · status='pending'",
    targetApp: TargetApp.OpenCodeTUI,
    targetRef: 'opencode TUI · ses_8f2a',
    itermTabIndex: 0,
    localPath: `${OPENCODE_DB_PATH} · session(ses_8f2a)`,
    updatedAt: '刚刚',
    summary: '已完成 Gin Context 零分配改造，opencode.db permission 表检测到待确认压测请求。',
    logLines: [
      'sqlite> SELECT id, parent_id, time_updated FROM session WHERE id = "ses_8f2a";',
      '',
      '● Master   已重写 internal/middleware/ratelimit.go (0 allocs/op)',
      '├─ @explore  session(ses_8f2a_sub1, parent_id="ses_8f2a") · 扫描 14 个路由挂载点',
      '└─ @general  permission(per_8f2a) 挂起: go test -bench=BenchmarkGinRouter ./...',
      '',
      '▸ 等待确认  [y] 允许执行   [a] 始终允许   [n] 取消',
    ],
    subTasks: [
      {
        id: 'sub-01a',
        parentId: 'master-confirm-01',
        title: '扫描 gin.RouterGroup 路由树依赖',
        subagentRole: '@explore',
        status: AgentStatus.Completed,
        stateEnteredAt: BOOT_TS - 42_000,
        dbRecordRef: 'message(msg_104a) · time.completed',
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 2',
        itermTabIndex: 1,
        elapsed: '1.1s',
        localOffset: 'prt_104a',
        logLines: [
          'opencode.db -> session(parent_id="ses_8f2a") · part(prt_104a, type="step-finish")',
          'internal/server/http.go:28: v1 := engine.Group("/api/v1")',
          '[@explore] 14 endpoints verified, zero circular middleware.',
        ],
      },
      {
        id: 'sub-01b',
        parentId: 'master-confirm-01',
        title: '运行 Gin 路由压测脚本确认',
        subagentRole: '@general',
        status: AgentStatus.Confirm,
        stateEnteredAt: BOOT_TS - 7_000,
        dbRecordRef: "permission(per_104b) · status='pending'",
        targetApp: TargetApp.OpenCodeTUI,
        targetRef: 'opencode TUI · 主窗口',
        itermTabIndex: 0,
        elapsed: '待确认',
        localOffset: 'per_104b',
        logLines: [
          'opencode.db -> permission(id="per_104b", session_id="ses_8f2a")',
          'Tool request: bash `go test -bench=BenchmarkGinRouter -benchmem ./...`',
        ],
      },
    ],
  },
  {
    id: 'master-running-02',
    title: '实现 opencode.db WAL 只读状态增量解析',
    engine: 'opencode',
    modelName: 'deepseek/deepseek-chat',
    status: AgentStatus.Working,
    stateEnteredAt: BOOT_TS - 12_000,
    dbRecordRef: "part(prt_4c91) · data.type='tool'",
    targetApp: TargetApp.ITerm2,
    targetRef: 'iTerm2 · Tab 1',
    itermTabIndex: 0,
    localPath: `${OPENCODE_DB_PATH} · session(ses_4c91)`,
    updatedAt: '3秒前',
    summary: '以 SQLITE_OPEN_READONLY 模式读取 opencode.db，按 project → session → message → part 构建实时状态树。',
    logLines: [
      'opencode  ses_4c91 · deepseek/deepseek-chat · opencode.db (WAL)',
      '',
      '● Master   正在编写 Sources/AgentSpur/OpenCodeDBReader.swift',
      '├─ @general  聚合 session(parent_id) 与 part(time_created) 状态切面 (0.14ms)',
      '└─ @explore  关联 session.directory 与 iTerm2 活跃 TTY 标签页',
    ],
    subTasks: [
      {
        id: 'sub-02a',
        parentId: 'master-running-02',
        title: '查询 part 表 tool/step-start 时间戳',
        subagentRole: '@general',
        status: AgentStatus.Working,
        stateEnteredAt: BOOT_TS - 11_000,
        dbRecordRef: "part(prt_209a) · data.type='tool'",
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 1',
        itermTabIndex: 0,
        elapsed: '11s',
        localOffset: 'prt_209a',
        logLines: [
          'SELECT id, time_created, json_extract(data, "$.type") FROM part WHERE session_id = "ses_4c91";',
          '12 active part rows parsed via SQLITE_OPEN_READONLY in 0.14ms.',
        ],
      },
      {
        id: 'sub-02b',
        parentId: 'master-running-02',
        title: '推导 session.directory 与 iTerm2 标签映射',
        subagentRole: '@explore',
        status: AgentStatus.Thinking,
        stateEnteredAt: BOOT_TS - 4_000,
        dbRecordRef: "part(prt_209b) · data.type='reasoning'",
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 3',
        itermTabIndex: 2,
        elapsed: '4s',
        localOffset: 'prt_209b',
        logLines: [
          'opencode.db -> part(id="prt_209b", data.type="reasoning")',
          'Matching project.worktree & tty /dev/ttys003 -> iTerm2 Tab 3...',
        ],
      },
    ],
  },
  {
    id: 'master-running-03',
    title: 'DeepSeek 角色包 15 FPS 纹理预烘焙',
    engine: 'DeepSeek',
    modelName: 'deepseek/deepseek-reasoner',
    status: AgentStatus.Thinking,
    stateEnteredAt: BOOT_TS - 4_000,
    dbRecordRef: "part(prt_77a) · data.type='reasoning'",
    targetApp: TargetApp.OpenCodeTUI,
    targetRef: 'opencode TUI · ses_77a',
    itermTabIndex: 1,
    localPath: `${OPENCODE_DB_PATH} · session(ses_77a)`,
    updatedAt: '4秒前',
    summary: '根据 opencode.db reasoning 分片实时驱动 15 FPS 思考涟漪动画，CPU 占用低于 0.1%。',
    logLines: [
      'opencode  ses_77a · deepseek/deepseek-reasoner · part.type="reasoning"',
      '',
      '◌ Thinking  计算 75 帧 36×36px 位图缓存布局 (总计约 388 KB)',
      '└─ @general  校准浅色磨砂菜单栏边缘抗锯齿',
    ],
    subTasks: [
      {
        id: 'sub-03a',
        parentId: 'master-running-03',
        title: '校准 Retina @2x 18pt 渲染锐度',
        subagentRole: '@general',
        status: AgentStatus.Working,
        stateEnteredAt: BOOT_TS - 8_000,
        dbRecordRef: "part(prt_311a) · data.type='tool'",
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 2',
        itermTabIndex: 1,
        elapsed: '8s',
        localOffset: 'prt_311a',
        logLines: [
          'opencode.db -> part(prt_311a) · CGContext 36×36px @2x verified.',
          'Frame draw latency: 0.06ms / frame @ 15 FPS.',
        ],
      },
    ],
  },
  {
    id: 'master-done-04',
    title: '绑定菜单栏额度显示与 ⌘R 快捷刷新',
    engine: 'opencode',
    modelName: 'deepseek/deepseek-chat',
    status: AgentStatus.Completed,
    stateEnteredAt: BOOT_TS - 304_000,
    dbRecordRef: 'message(msg_1d08) · time.completed',
    targetApp: TargetApp.ITerm2,
    targetRef: 'iTerm2 · Tab 2',
    itermTabIndex: 1,
    localPath: `${OPENCODE_DB_PATH} · session(ses_1d08)`,
    updatedAt: '5分钟前',
    duration: '1m 24s',
    summary: '聚合 opencode.db session.cost 与 tokens_* 统计，完成等宽数字防抖动渲染。',
    logLines: [
      '✓ Master   message(msg_1d08) time.completed - time.created = 84,000ms (耗时 1m 24s)',
      '└─ @general  聚合 session.cost 与 monospacedDigitSystemFont 零位移校验',
    ],
    subTasks: [
      {
        id: 'sub-04a',
        parentId: 'master-done-04',
        title: '菜单栏等宽数字防抖校验',
        subagentRole: '@general',
        status: AgentStatus.Completed,
        stateEnteredAt: BOOT_TS - 306_000,
        dbRecordRef: 'message(msg_401a) · time.completed',
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 2',
        itermTabIndex: 1,
        elapsed: '1.8s',
        localOffset: 'prt_401a',
        logLines: ['Verified 0px horizontal jitter on status item update (opencode.db).'],
      },
    ],
  },
  {
    id: 'master-done-06',
    title: '优化 Gin JSON 序列化零拷贝响应头',
    engine: 'opencode',
    modelName: 'deepseek/deepseek-reasoner',
    status: AgentStatus.Completed,
    stateEnteredAt: BOOT_TS - 725_000,
    dbRecordRef: 'message(msg_09c4) · time.completed',
    targetApp: TargetApp.OpenCodeTUI,
    targetRef: 'opencode TUI · ses_09c4',
    itermTabIndex: 0,
    localPath: `${OPENCODE_DB_PATH} · session(ses_09c4)`,
    updatedAt: '12分钟前',
    duration: '38s',
    summary: '完成 gin.Context 响应缓冲池复用，opencode.db 记录总执行耗时 38s。',
    logLines: [
      '✓ Master   message(msg_09c4) completed in 38,000ms (耗时 38s)',
      '└─ @explore  对比 10k 并发下 sync.Pool 内存分配曲线',
    ],
    subTasks: [
      {
        id: 'sub-06a',
        parentId: 'master-done-06',
        title: '采集 sync.Pool 内存分配基准',
        subagentRole: '@explore',
        status: AgentStatus.Completed,
        stateEnteredAt: BOOT_TS - 730_000,
        dbRecordRef: 'message(msg_601a) · time.completed',
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 1',
        itermTabIndex: 0,
        elapsed: '4.2s',
        localOffset: 'prt_601a',
        logLines: ['BenchmarkJSONPool-12  1000000  112 ns/op  0 B/op  0 allocs/op'],
      },
    ],
  },
  {
    id: 'master-err-05',
    title: '校验异常 Tool 调用快照只读隔离机制',
    engine: 'DeepSeek',
    modelName: 'deepseek/deepseek-chat',
    status: AgentStatus.Error,
    stateEnteredAt: BOOT_TS - 1_082_000,
    dbRecordRef: "part(prt_err02) · state.status='error'",
    targetApp: TargetApp.ITerm2,
    targetRef: 'iTerm2 · Tab 4',
    itermTabIndex: 3,
    localPath: `${OPENCODE_DB_PATH} · session(ses_err02)`,
    updatedAt: '18分钟前',
    duration: '0.4s',
    summary: 'opencode.db part 表捕获 tool 返回非零退出码，已隔离异常状态并保持只读稳定。',
    logLines: [
      '✕ Error    opencode.db -> part(prt_err02) json_extract(data, "$.state.status") = "error"',
      '└─ @explore  已记录异常起始时间 time_created，菜单栏触发 15 FPS 出错提醒',
    ],
    subTasks: [
      {
        id: 'sub-05a',
        parentId: 'master-err-05',
        title: '定位 part 异常退出码记录',
        subagentRole: '@explore',
        status: AgentStatus.Error,
        stateEnteredAt: BOOT_TS - 1_082_000,
        dbRecordRef: "part(prt_501a) · state.status='error'",
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 4',
        itermTabIndex: 3,
        elapsed: '0.2s',
        localOffset: 'prt_501a',
        logLines: ['Read part(prt_501a) via SQLITE_OPEN_READONLY without locking WAL.'],
      },
    ],
  },
];

export const INITIAL_WEEKLY_EFFICIENCY: WeeklyEfficiencyPoint[] = [
  { day: '周三', dateShort: '10/21', tasksPerHour: 6.4, avgSeconds: 58, completedCount: 15 },
  { day: '周四', dateShort: '10/22', tasksPerHour: 7.2, avgSeconds: 52, completedCount: 18 },
  { day: '周五', dateShort: '10/23', tasksPerHour: 8.5, avgSeconds: 45, completedCount: 23 },
  { day: '周六', dateShort: '10/24', tasksPerHour: 6.9, avgSeconds: 49, completedCount: 12 },
  { day: '周日', dateShort: '10/25', tasksPerHour: 7.8, avgSeconds: 44, completedCount: 16 },
  { day: '周一', dateShort: '10/26', tasksPerHour: 9.4, avgSeconds: 39, completedCount: 26 },
  { day: '周二', dateShort: '10/27', tasksPerHour: 10.8, avgSeconds: 34, completedCount: 21, isToday: true },
];

export const NATIVE_SWIFT_PACKAGE_CODE = `// swift-tools-version: 5.10
// 极简纯原生 AppKit + SQLite3 · 无 WebView · 无常驻后台守护进程 · 严格基于 opencode.db 只读解析
import PackageDescription

let package = Package(
    name: "AgentSpur",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AgentSpur",
            path: "Sources/AgentSpur",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("CoreServices"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)`;

export const NATIVE_SWIFT_APPKIT_CODE = `import AppKit
import CoreServices
import SQLite3
import UserNotifications

enum AgentRunState: String, Codable, CaseIterable {
    case thinking   = "思考"
    case working    = "工作"
    case confirm    = "等你确认"
    case completed  = "完成"
    case error      = "出错"

    var livePrefix: String {
        switch self {
        case .thinking:  return "正在思考"
        case .working:   return "正在工作"
        case .confirm:   return "等你确认"
        case .completed: return "已完成"
        case .error:     return "已出错"
        }
    }
}

struct SessionStateRow {
    let sessionId: String
    let parentId: String?
    let title: String
    var state: AgentRunState
    var stateEnteredAtMs: Int64 // 严格源自 opencode.db part/permission/session 时间戳，状态切换时自动重置
}

@main
final class AgentSpurApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var animTimer: Timer?
    private var frameIndex: Int = 0
    private var currentState: AgentRunState = .thinking
    private var stateEnteredAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    private var silentAlertEnabled: Bool = true
    private var quotaText: String = "$24.85 · 04:00"
    private let dbPath = ("~/.local/share/opencode/opencode.db" as NSString).expandingTildeInPath

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // 纯菜单栏轻量应用
        let delegate = AgentSpurApp()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureMenu()
        pollOpencodeDbReadOnly()
        start15FPSAnimationLoop()
        watchOpencodeDbWALReadOnly()
    }

    private func applyState(_ next: AgentRunState, enteredAtMs: Int64? = nil) {
        if next != currentState {
            currentState = next
            // 状态发生切换时，计时自动重置为最新状态进入时间戳
            stateEnteredAtMs = enteredAtMs ?? Int64(Date().timeIntervalSince1970 * 1000)
        }
    }

    private func pollOpencodeDbReadOnly() {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }

        // 严格依据 opencode.db: project -> session(parent_id) -> message -> part / permission
        let sql = """
        SELECT s.id, s.parent_id, s.title, p.time_created, json_extract(p.data, '$.type')
        FROM session s
        LEFT JOIN part p ON p.session_id = s.id
        ORDER BY p.time_created DESC LIMIT 1;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                let partTimeMs = sqlite3_column_int64(stmt, 3)
                let partType = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
                let mapped: AgentRunState = (partType == "reasoning") ? .thinking : .working
                applyState(mapped, enteredAtMs: partTimeMs > 0 ? partTimeMs : nil)
            }
            sqlite3_finalize(stmt)
        }
    }

    private func start15FPSAnimationLoop() {
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            guard let self, let button = self.statusItem.button else { return }
            self.frameIndex = (self.frameIndex + 1) % 15
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let sec = max(0, (nowMs - self.stateEnteredAtMs) / 1000)
            button.image = self.renderStatusFrame(state: self.currentState, frame: self.frameIndex)
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(
                string: " \\(self.currentState.livePrefix) \\(sec)s · \\(self.quotaText)",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]
            )
        }
        RunLoop.main.add(animTimer!, forMode: .common)
    }

    @objc private func refreshQuota(_ sender: Any?) {
        pollOpencodeDbReadOnly()
    }

    private func renderStatusFrame(state: AgentRunState, frame: Int) -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.labelColor.setStroke()
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5))
            path.lineWidth = 1.5
            path.stroke()
            return true
        }
    }

    private func configureMenu() {
        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "刷新额度与 opencode.db", action: #selector(refreshQuota(_:)), keyEquivalent: "r")
        refreshItem.keyEquivalentModifierMask = [.command]
        menu.addItem(refreshItem)
        statusItem.menu = menu
    }

    private func watchOpencodeDbWALReadOnly() {
        // FSEventStream 监听 ~/.local/share/opencode/opencode.db-wal 变化并触发只读增量查询
    }
}`;
