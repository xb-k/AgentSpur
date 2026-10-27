import {
  AgentStatus,
  CharacterPack,
  MasterSession,
  QuotaState,
  TargetApp,
  WeeklyEfficiencyPoint,
} from '../types/agent';

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
    targetApp: TargetApp.OpenCodeTUI,
    targetRef: 'opencode TUI · ses_8f2a',
    itermTabIndex: 0,
    localPath: '~/.local/share/opencode/storage/session/ses_8f2a.json',
    updatedAt: '刚刚',
    summary: '已完成 Gin Context 零分配改造，等待你在 opencode TUI 确认执行基准测试。',
    logLines: [
      'opencode  ses_8f2a · deepseek/deepseek-reasoner',
      '',
      '● Master   已重写 internal/middleware/ratelimit.go (0 allocs/op)',
      '├─ @explore  已扫描 14 个 gin.RouterGroup 路由挂载点',
      '└─ @general  请求执行: go test -bench=BenchmarkGinRouter ./... ',
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
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 2',
        itermTabIndex: 1,
        elapsed: '1.1s',
        localOffset: 'prt_104a',
        logLines: [
          '$ rg "RouterGroup" internal/server/',
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
        targetApp: TargetApp.OpenCodeTUI,
        targetRef: 'opencode TUI · 主窗口',
        itermTabIndex: 0,
        elapsed: '待确认',
        localOffset: 'prt_104b',
        logLines: [
          'Tool request: bash `go test -bench=BenchmarkGinRouter -benchmem ./...`',
          'Awaiting confirmation in opencode TUI...',
        ],
      },
    ],
  },
  {
    id: 'master-running-02',
    title: '实现 FSEvents 本机会话只读增量解析',
    engine: 'opencode',
    modelName: 'deepseek/deepseek-chat',
    status: AgentStatus.Working,
    targetApp: TargetApp.ITerm2,
    targetRef: 'iTerm2 · Tab 1',
    itermTabIndex: 0,
    localPath: '~/.local/share/opencode/storage/session/ses_4c91.json',
    updatedAt: '3秒前',
    summary: '按需监听 opencode 本地会话目录，构建零后台常驻进程的轻量状态树。',
    logLines: [
      'opencode  ses_4c91 · deepseek/deepseek-chat',
      '',
      '● Master   正在编写 Sources/AgentSpur/OpenCodeStore.swift',
      '├─ @general  增量映射 session/ 与 part/ 状态节点 (0.18ms)',
      '└─ @explore  解析 iTerm2 当前活跃 TTY 会话标识',
    ],
    subTasks: [
      {
        id: 'sub-02a',
        parentId: 'master-running-02',
        title: '读取 storage/part 增量偏移',
        subagentRole: '@general',
        status: AgentStatus.Working,
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 1',
        itermTabIndex: 0,
        elapsed: '12s',
        localOffset: 'prt_209a',
        logLines: [
          'Reading ~/.local/share/opencode/storage/part (O_RDONLY)',
          '12 active state slices parsed in 0.18ms.',
        ],
      },
      {
        id: 'sub-02b',
        parentId: 'master-running-02',
        title: '推导 opencode 进程与 iTerm2 标签页映射',
        subagentRole: '@explore',
        status: AgentStatus.Thinking,
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 3',
        itermTabIndex: 2,
        elapsed: '6s',
        localOffset: 'prt_209b',
        logLines: [
          'Inspecting tty /dev/ttys003 -> iTerm2 Window 1, Tab 3',
          'Planning instant AppleScript focus jump...',
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
    targetApp: TargetApp.OpenCodeTUI,
    targetRef: 'opencode TUI · ses_77a',
    itermTabIndex: 1,
    localPath: '~/.local/share/opencode/storage/session/ses_77a.json',
    updatedAt: '9秒前',
    summary: '预生成 5 状态 × 15 帧 Retina 位图序列，菜单栏播放 CPU 占用低于 0.1%。',
    logLines: [
      'opencode  ses_77a · deepseek/deepseek-reasoner',
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
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 2',
        itermTabIndex: 1,
        elapsed: '8s',
        localOffset: 'prt_311a',
        logLines: [
          'CGContext 36×36px @2x scale verified.',
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
    targetApp: TargetApp.ITerm2,
    targetRef: 'iTerm2 · Tab 2',
    itermTabIndex: 1,
    localPath: '~/.local/share/opencode/storage/session/ses_1d08.json',
    updatedAt: '5分钟前',
    duration: '1m 24s',
    summary: '已完成等宽数字防抖动渲染与静音完成提醒开关。',
    logLines: [
      '✓ Master   QuotaFormatter.swift 构建通过 (耗时 1m 24s)',
      '└─ @general  验证 monospacedDigitSystemFont 零位移抖动',
    ],
    subTasks: [
      {
        id: 'sub-04a',
        parentId: 'master-done-04',
        title: '菜单栏等宽数字防抖校验',
        subagentRole: '@general',
        status: AgentStatus.Completed,
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 2',
        itermTabIndex: 1,
        elapsed: '1.8s',
        localOffset: 'prt_401a',
        logLines: ['Verified 0px horizontal jitter on status item update.'],
      },
    ],
  },
  {
    id: 'master-done-06',
    title: '优化 Gin JSON 序列化零拷贝响应头',
    engine: 'opencode',
    modelName: 'deepseek/deepseek-reasoner',
    status: AgentStatus.Completed,
    targetApp: TargetApp.OpenCodeTUI,
    targetRef: 'opencode TUI · ses_09c4',
    itermTabIndex: 0,
    localPath: '~/.local/share/opencode/storage/session/ses_09c4.json',
    updatedAt: '12分钟前',
    duration: '38s',
    summary: '完成 gin.Context 响应缓冲池复用，P99 延迟下降 21%。',
    logLines: [
      '✓ Master   internal/render/json_pool.go 基准校验通过 (耗时 38s)',
      '└─ @explore  对比 10k 并发下 sync.Pool 内存分配曲线',
    ],
    subTasks: [
      {
        id: 'sub-06a',
        parentId: 'master-done-06',
        title: '采集 sync.Pool 内存分配基准',
        subagentRole: '@explore',
        status: AgentStatus.Completed,
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
    title: '校验损坏会话快照隔离机制',
    engine: 'DeepSeek',
    modelName: 'deepseek/deepseek-chat',
    status: AgentStatus.Error,
    targetApp: TargetApp.ITerm2,
    targetRef: 'iTerm2 · Tab 4',
    itermTabIndex: 3,
    localPath: '~/.local/share/opencode/storage/session/ses_corrupt_02.json',
    updatedAt: '18分钟前',
    duration: '0.4s',
    summary: '检测到归档 JSON 截断，已自动跳过并保持状态栏只读稳定。',
    logLines: [
      '✕ Error    Unexpected EOF at ses_corrupt_02.json:4192',
      '└─ @explore  已隔离异常分片，菜单栏触发 15 FPS 出错提醒',
    ],
    subTasks: [
      {
        id: 'sub-05a',
        parentId: 'master-err-05',
        title: '隔离截断 JSON 分片记录',
        subagentRole: '@explore',
        status: AgentStatus.Error,
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 4',
        itermTabIndex: 3,
        elapsed: '0.2s',
        localOffset: 'byte 4192',
        logLines: ['Isolated malformed JSON slice cleanly (O_RDONLY).'],
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
// 极简纯原生 AppKit · 无 WebView · 无常驻后台守护进程
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
                .linkedFramework("CoreServices")
            ]
        )
    ]
)`;

export const NATIVE_SWIFT_APPKIT_CODE = `import AppKit
import CoreServices
import UserNotifications

enum AgentRunState: String, Codable, CaseIterable {
    case thinking   = "思考"
    case working    = "工作"
    case confirm    = "等你确认"
    case completed  = "完成"
    case error      = "出错"
}

struct DeepSeekRolePack: Codable {
    let id: String
    let name: String
    let deepseekModel: String
    let primaryColor: String
    let customBaseSprite: [String]?
}

@main
final class AgentSpurApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var animTimer: Timer?
    private var frameIndex: Int = 0
    private var currentState: AgentRunState = .working
    private var silentAlertEnabled: Bool = true
    private var quotaText: String = "$24.85 · 04:00"

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
        start15FPSAnimationLoop()
        watchOpenCodeStorageReadOnly()
    }

    private func start15FPSAnimationLoop() {
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            guard let self, let button = self.statusItem.button else { return }
            self.frameIndex = (self.frameIndex + 1) % 15
            button.image = self.renderStatusFrame(state: self.currentState, frame: self.frameIndex)
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(
                string: " \\(self.currentState.rawValue) · \\(self.quotaText)",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]
            )
        }
        RunLoop.main.add(animTimer!, forMode: .common)
    }

    @objc private func jumpToOpenCodeSession(_ sender: NSMenuItem) {
        guard let tabIdx = sender.representedObject as? Int else { return }
        let script = """
        tell application "iTerm2"
            activate
            tell current window to select tab \\(tabIdx)
        end tell
        """
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    @objc private func refreshQuota(_ sender: Any?) {
        self.quotaText = "$24.85 · 04:00"
    }

    private func postSilentCompletionBanner(taskTitle: String) {
        guard silentAlertEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "AgentSpur · opencode 任务已完成"
        content.body = taskTitle
        content.sound = nil
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
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
        let refreshItem = NSMenuItem(title: "刷新额度", action: #selector(refreshQuota(_:)), keyEquivalent: "r")
        refreshItem.keyEquivalentModifierMask = [.command]
        menu.addItem(refreshItem)
        statusItem.menu = menu
    }

    private func watchOpenCodeStorageReadOnly() {
        // FSEventStream 只读监听 ~/.local/share/opencode/storage/session
    }
}`;
