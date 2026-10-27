import {
  AgentStatus,
  CharacterPack,
  MasterSession,
  QuotaState,
  TargetApp,
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
    shortVerb: '推理规划中',
    colorHex: '#0284C7',
    textClass: 'text-sky-700',
    frameNote: '15 FPS · 脉冲视线与思维涟漪 (15帧循环)',
  },
  [AgentStatus.Working]: {
    label: '工作',
    shortVerb: '读写执行中',
    colorHex: '#0F172A',
    textClass: 'text-slate-900',
    frameNote: '15 FPS · 高频敲击与推进节拍 (15帧循环)',
  },
  [AgentStatus.Confirm]: {
    label: '等你确认',
    shortVerb: '等待权限确认',
    colorHex: '#D97706',
    textClass: 'text-amber-700',
    frameNote: '15 FPS · 举手示意与呼吸信标 (15帧循环)',
  },
  [AgentStatus.Completed]: {
    label: '完成',
    shortVerb: '任务已就绪',
    colorHex: '#16A34A',
    textClass: 'text-emerald-700',
    frameNote: '15 FPS · 勾画收尾与静息微动 (15帧循环)',
  },
  [AgentStatus.Error]: {
    label: '出错',
    shortVerb: '进程异常中断',
    colorHex: '#DC2626',
    textClass: 'text-rose-700',
    frameNote: '15 FPS · 微幅抖动与诊断警示 (15帧循环)',
  },
};

export const BUILTIN_CHARACTER_PACKS: CharacterPack[] = [
  {
    id: 'pack-deepseek-whale',
    name: '深海小鲸 · 原生版',
    author: 'DeepSeek Community',
    version: '1.2.0',
    deepseekModel: 'deepseek/deepseek-reasoner',
    roleDescription: '清爽明亮菜单栏配色的微缩蓝鲸角色包，以声呐气泡与尾鳍节拍呈现 15 FPS 五状态。',
    archetype: 'whale',
    primaryColor: '#0284C7',
    secondaryColor: '#0EA5E9',
    isBuiltIn: true,
  },
  {
    id: 'pack-appkit-glyph',
    name: 'AppKit 纯粹单色',
    author: 'macOS Native HIG',
    version: '2.0.0',
    deepseekModel: 'deepseek/deepseek-chat',
    roleDescription: '遵循 Apple 浅色菜单栏 NSImage.isTemplate 墨黑单色规范，零干扰融入系统状态栏。',
    archetype: 'glyph',
    primaryColor: '#0F172A',
    secondaryColor: '#475569',
    isBuiltIn: true,
  },
  {
    id: 'pack-deepseek-neko',
    name: '晴空像素猫',
    author: 'PixelCraft Studio',
    version: '1.4.2',
    deepseekModel: 'deepseek/deepseek-chat',
    roleDescription: '经典 Mac 菜单栏像素灵猫，思考时抬头凝视气泡，工作时双爪在状态栏边缘交替敲击。',
    archetype: 'neko',
    primaryColor: '#1E293B',
    secondaryColor: '#D97706',
    isBuiltIn: true,
  },
  {
    id: 'pack-deepseek-kitsune',
    name: '玄机折纸狐',
    author: 'Kitsune Lab',
    version: '1.0.5',
    deepseekModel: 'deepseek/deepseek-reasoner',
    roleDescription: '面向代码审计与安全验证的几何灵狐角色包，双耳随等你确认与报错状态实时反馈。',
    archetype: 'kitsune',
    primaryColor: '#EA580C',
    secondaryColor: '#0284C7',
    isBuiltIn: true,
  },
];

export const SAMPLE_CUSTOM_PACK_JSON = {
  id: 'custom-deepseek-owl-01',
  name: '晴昼机械鸮 (自定义包)',
  author: 'Local Mac User',
  version: '1.0.0',
  deepseekModel: 'deepseek/deepseek-reasoner',
  roleDescription: '导入自本地 ~/.config/opencode/roles/day_owl.json 的自定义角色包，支持 12x12 点阵与五态帧动画。',
  archetype: 'custom_pixel',
  primaryColor: '#0369A1',
  secondaryColor: '#D97706',
  customBaseSprite: [
    '..##....##..',
    '.##########.',
    '###++##++###',
    '###++##++###',
    '############',
    '.####++####.',
    '.##########.',
    '..########..',
    '..########..',
    '...##..##...',
    '..###..###..',
    '............',
  ],
};

export const INITIAL_QUOTA: QuotaState = {
  remainingUsd: 24.85,
  totalUsd: 35.0,
  resetTimeLabel: '04:00重置',
  resetCountdown: '02h 58m',
  lastRefreshedAt: '01:02:27',
};

export const INITIAL_SESSIONS: MasterSession[] = [
  {
    id: 'master-confirm-01',
    title: '迁移 AppKit NSStatusItem 渲染管线并移除 WebView 依赖',
    engine: 'opencode',
    modelName: 'deepseek/deepseek-reasoner',
    status: AgentStatus.Confirm,
    targetApp: TargetApp.OpenCodeTUI,
    targetRef: 'opencode TUI · 主窗口 (ses_8f2a)',
    itermTabIndex: 0,
    localPath: '~/.local/share/opencode/storage/session/ses_8f2a.json',
    updatedAt: '刚刚',
    summary: 'Master Agent 已生成 AppKit 帧缓存补丁，子任务正在 opencode TUI 等待 bash 权限确认。',
    logLines: [
      '┌─ opencode v0.3 · session ses_8f2a · model: deepseek/deepseek-reasoner ─┐',
      '│ [Master] Read Sources/AgentBar/StatusBarController.swift (mmap readonly)',
      '│ [@explore] Verified 0 WebKit.framework symbols in release binary',
      '│ [@general] Permission required: bash `codesign --entitlements AgentBar.entitlements`',
      '└─ [Allow (y)]  [Allow Always (a)]  [Deny (n)] ── Waiting in opencode TUI ─┘',
    ],
    subTasks: [
      {
        id: 'sub-01a',
        parentId: 'master-confirm-01',
        title: '扫描 Mach-O 符号表确认零 WebKit 动态库链接',
        subagentRole: '@explore',
        status: AgentStatus.Completed,
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 2 (opencode @explore)',
        itermTabIndex: 1,
        elapsed: '1.4s',
        localOffset: 'part/prt_104a.json',
        logLines: [
          '$ otool -L .build/release/AgentBar',
          '  /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit',
          '  /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation',
          '[@explore] Done: 0 WebView dependencies linked. Memory RSS = 11.2 MB.',
        ],
      },
      {
        id: 'sub-01b',
        parentId: 'master-confirm-01',
        title: '请求写入只读沙盒权限配置 (AgentBar.entitlements)',
        subagentRole: '@general',
        status: AgentStatus.Confirm,
        targetApp: TargetApp.OpenCodeTUI,
        targetRef: 'opencode TUI · 权限确认框 #12-B',
        itermTabIndex: 0,
        elapsed: '等待确认',
        localOffset: 'part/prt_104b.json',
        logLines: [
          'opencode TUI Tool Call -> write("Resources/AgentBar.entitlements")',
          '+ com.apple.security.files.home-relative-path.read-only:',
          '+   - /.local/share/opencode/storage/',
          '+   - /.config/opencode/roles/',
          'Waiting for user confirmation inside opencode TUI...',
        ],
      },
    ],
  },
  {
    id: 'master-running-02',
    title: '基于 FSEvents 按需解析本机 opencode 会话树与子 Agent 状态',
    engine: 'opencode',
    modelName: 'deepseek/deepseek-chat',
    status: AgentStatus.Working,
    targetApp: TargetApp.ITerm2,
    targetRef: 'iTerm2 · Tab 1 (opencode)',
    itermTabIndex: 0,
    localPath: '~/.local/share/opencode/storage/session/ses_4c91.json',
    updatedAt: '3秒前',
    summary: '正在构建无常驻守护进程的 FSEvents 文件变更回调与 parentID 子任务树映射。',
    logLines: [
      '┌─ opencode TUI · iTerm2 Tab 1 · ~/.local/share/opencode/storage/ ───────┐',
      '│ [Master] Watching session/ & part/ directories via macOS FSEvents',
      '│ [@general] Linking child session parentID -> Master session node',
      '│ [Master] Applying edit to Sources/AgentBar/OpenCodeStore.swift...',
      '└─ tab: build · working @ 15 FPS ─────────────────────────────────────────┘',
    ],
    subTasks: [
      {
        id: 'sub-02a',
        parentId: 'master-running-02',
        title: '增量读取 storage/part 状态文件避免全量扫描',
        subagentRole: '@general',
        status: AgentStatus.Working,
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 1 (opencode)',
        itermTabIndex: 0,
        elapsed: '16s',
        localOffset: 'part/prt_209a.json',
        logLines: [
          'opencode subagent (@general) running tool: bash `swift test --filter OpenCodeStoreTests`',
          'Parsed 12 session metadata files in 0.19ms (O_RDONLY, zero lock contention).',
        ],
      },
      {
        id: 'sub-02b',
        parentId: 'master-running-02',
        title: '推导 opencode 进程 TTY 与 iTerm2 标签页定位映射',
        subagentRole: '@explore',
        status: AgentStatus.Thinking,
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 3 (opencode-tty)',
        itermTabIndex: 2,
        elapsed: '8s',
        localOffset: 'part/prt_209b.json',
        logLines: [
          'opencode subagent (@explore) inspecting lsof tty descriptors...',
          'Mapped PID 51902 (opencode) -> /dev/ttys003 -> iTerm2 Window 1, Tab 3.',
        ],
      },
    ],
  },
  {
    id: 'master-running-03',
    title: 'DeepSeek 角色包 15 FPS 位图纹理预烘焙与切换热加载',
    engine: 'DeepSeek',
    modelName: 'deepseek/deepseek-reasoner',
    status: AgentStatus.Thinking,
    targetApp: TargetApp.OpenCodeTUI,
    targetRef: 'opencode TUI · 会话 ses_77a',
    itermTabIndex: 1,
    localPath: '~/.local/share/opencode/storage/session/ses_77a.json',
    updatedAt: '9秒前',
    summary: 'DeepSeek-R1 Master Agent 正在规划自定义角色包五套动作序列的 Retina @2x 纹理缓存。',
    logLines: [
      '┌─ opencode TUI · model: deepseek/deepseek-reasoner ─────────────────────┐',
      '│ <thought> 5 states × 15 frames = 75 pre-rendered CGImage bitmaps.',
      '│ Memory footprint: 75 × (36×36×4 bytes) ≈ 388 KB total in NSStatusItem.',
      '└─ [@general] Verifying light/dark menu bar appearance vibrancy ─────────┘',
    ],
    subTasks: [
      {
        id: 'sub-03a',
        parentId: 'master-running-03',
        title: '校验浅色菜单栏 Retina @2x 18pt 边界对比度',
        subagentRole: '@general',
        status: AgentStatus.Working,
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 2 (opencode @explore)',
        itermTabIndex: 1,
        elapsed: '11s',
        localOffset: 'part/prt_311a.json',
        logLines: [
          'Rendering CGContext(width: 36, height: 36) for macOS Aqua Light Menu Bar...',
          'Frame budget at 15 FPS = 66.67ms; actual CPU blit time = 0.07ms/frame.',
        ],
      },
    ],
  },
  {
    id: 'master-done-04',
    title: '菜单栏剩余额度直显与 ⌘R 快捷键局部刷新绑定',
    engine: 'opencode',
    modelName: 'deepseek/deepseek-chat',
    status: AgentStatus.Completed,
    targetApp: TargetApp.ITerm2,
    targetRef: 'iTerm2 · Tab 2 (opencode)',
    itermTabIndex: 1,
    localPath: '~/.local/share/opencode/storage/session/ses_1d08.json',
    updatedAt: '5分钟前',
    summary: '已完成额度等宽数字渲染与静音通知开关持久化，零后台常驻轮询。',
    logLines: [
      '[opencode] Applied patch to Sources/AgentBar/QuotaFormatter.swift',
      '[opencode] Bound NSMenuItem(title: "刷新额度", keyEquivalent: "r")',
      '[completed] Build & check succeeded in 1.8s.',
    ],
    subTasks: [
      {
        id: 'sub-04a',
        parentId: 'master-done-04',
        title: '绑定 monospacedDigitSystemFont 消除菜单栏跳字抖动',
        subagentRole: '@general',
        status: AgentStatus.Completed,
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 2 (opencode)',
        itermTabIndex: 1,
        elapsed: '2.0s',
        localOffset: 'part/prt_401a.json',
        logLines: [
          'Applied NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)',
          'Verified 0px horizontal jitter on macOS status bar.',
        ],
      },
    ],
  },
  {
    id: 'master-err-05',
    title: '解析旧版损坏会话分片 (ses_corrupt_02.json)',
    engine: 'DeepSeek',
    modelName: 'deepseek/deepseek-chat',
    status: AgentStatus.Error,
    targetApp: TargetApp.ITerm2,
    targetRef: 'iTerm2 · Tab 4 (opencode-debug)',
    itermTabIndex: 3,
    localPath: '~/.local/share/opencode/storage/session/ses_corrupt_02.json',
    updatedAt: '18分钟前',
    summary: '本地分片 JSON 尾部截断，已自动隔离异常记录并保持状态栏只读安全。',
    logLines: [
      '[opencode-store] Opening ~/.local/share/opencode/storage/session/ses_corrupt_02.json (O_RDONLY)',
      '[error] Unexpected EOF at byte 4192 — isolated corrupted snapshot cleanly.',
    ],
    subTasks: [
      {
        id: 'sub-05a',
        parentId: 'master-err-05',
        title: '验证损坏分片跳过与菜单栏报错动画触发',
        subagentRole: '@explore',
        status: AgentStatus.Error,
        targetApp: TargetApp.ITerm2,
        targetRef: 'iTerm2 · Tab 4 (opencode-debug)',
        itermTabIndex: 3,
        elapsed: '0.3s',
        localOffset: 'byte 4192',
        logLines: [
          'Error: NSCocoaErrorDomain Code=3840 "Unexpected end of file"',
          'Switched menu bar NSStatusItem to 15 FPS Error sequence.',
        ],
      },
    ],
  },
];

export const NATIVE_SWIFT_PACKAGE_CODE = `// swift-tools-version: 5.10
// 零第三方依赖 · 纯原生 AppKit · 无 WebView · 无常驻后台守护进程
import PackageDescription

let package = Package(
    name: "AgentBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AgentBar",
            path: "Sources/AgentBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("CoreServices") // FSEvents 本机 opencode 会话只读监听
            ]
        )
    ]
)`;

export const NATIVE_SWIFT_APPKIT_CODE = `import AppKit
import CoreServices
import UserNotifications

// MARK: - 五套实时状态（菜单栏 15 FPS 原生帧动画）
enum AgentRunState: String, Codable, CaseIterable {
    case thinking   = "思考"
    case working    = "工作"
    case confirm    = "等你确认"
    case completed  = "完成"
    case error      = "出错"
}

// MARK: - DeepSeek 自定义角色包清单（本机只读导入）
struct DeepSeekRolePack: Codable {
    let id: String
    let name: String
    let deepseekModel: String
    let primaryColor: String
    let customBaseSprite: [String]?
}

// MARK: - AppKit 纯原生菜单栏控制器（无 WebView · 仅展示看）
@main
final class AgentBarApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var animTimer: Timer?
    private var frameIndex: Int = 0
    private var currentState: AgentRunState = .working
    private var silentAlertEnabled: Bool = true
    private var quotaText: String = "$24.85 · 04:00重置"

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // LSUIElement 纯菜单栏应用，不占 Dock
        let delegate = AgentBarApp()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureMenu()
        start15FPSAnimationLoop()
        watchOpenCodeStorageReadOnly() // 仅在本机只读 ~/.local/share/opencode/storage
    }

    // 严格 15 FPS (66.67ms/帧) 播放当前状态帧序列
    private func start15FPSAnimationLoop() {
        let interval = 1.0 / 15.0
        animTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, let button = self.statusItem.button else { return }
            self.frameIndex = (self.frameIndex + 1) % 15
            button.image = self.renderStatusFrame(state: self.currentState, frame: self.frameIndex)
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(
                string: " \\(self.currentState.rawValue) · \\(self.quotaText)",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
                ]
            )
        }
        RunLoop.main.add(animTimer!, forMode: .common)
    }

    // 点一下跳回运行 opencode TUI 的终端窗口或指定 iTerm2 标签页
    @objc private func jumpToOpenCodeSession(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? String else { return }
        if target.hasPrefix("iterm2-tab:") {
            let tabIdx = target.replacingOccurrences(of: "iterm2-tab:", with: "")
            let script = """
            tell application "iTerm2"
                activate
                tell current window to select tab \\(tabIdx)
            end tell
            """
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        } else if target.hasPrefix("tty:") {
            let ttyPath = target.replacingOccurrences(of: "tty:", with: "")
            let script = """
            tell application "iTerm2"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\\(ttyPath)" then
                                select t
                                select s
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
    }

    // ⌘R 刷新本机额度快照
    @objc private func refreshQuota(_ sender: Any?) {
        // 仅读取本机额度缓存并刷新菜单栏标题
        self.quotaText = "$24.85 · 04:00重置"
    }

    // 任务跑完弹静音通知（sound = nil，可随时关闭）
    private func postSilentCompletionBanner(taskTitle: String) {
        guard silentAlertEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "opencode 任务已完成"
        content.body = taskTitle
        content.sound = nil // 严格静音通知
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func renderStatusFrame(state: AgentRunState, frame: Int) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.labelColor.setStroke()
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            path.lineWidth = 1.5
            path.stroke()
            return true
        }
    }

    private func configureMenu() {
        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "刷新额度与 opencode 会话", action: #selector(refreshQuota(_:)), keyEquivalent: "r")
        refreshItem.keyEquivalentModifierMask = [.command]
        menu.addItem(refreshItem)
        statusItem.menu = menu
    }

    private func watchOpenCodeStorageReadOnly() {
        // 使用 FSEventStream 监听 ~/.local/share/opencode/storage/session 变更，O_RDONLY 本机只读
    }
}`;
