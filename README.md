# AgentSpur (macOS 原生菜单栏应用)

**AgentSpur** 是一款纯原生 macOS `AppKit` 菜单栏 Agent 状态监控工具（**无 WebView · 无 Electron · 无后端服务 · 无常驻守护进程**），专为 `opencode TUI` 与 `iTerm2` 打造，严格以 `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX` 只读方式解析本机 `~/.local/share/opencode/opencode.db`。

---

## 一键打包成 `.dmg` 安装镜像（推荐）

系统要求：**macOS 14.0 (Sonoma) 及以上**，并已安装系统自带编译工具链（若未安装，终端执行 `xcode-select --install` 即可，无需安装完整版 Xcode，无需安装任何第三方依赖）。

### 方法 A：在访达 (Finder) 中直接双击打包
1. 将源码下载并解压到 Mac 任意目录。
2. 直接双击目录中的 **`双击打包DMG.command`**（若首次提示权限，可在终端执行一次 `chmod +x build_dmg.sh 双击打包DMG.command`）。
3. 脚本会自动编译 Release 二进制、渲染生成高清冰瓷流体专属图标 `AppIcon.icns`、组装 `AgentSpur.app`、完成本机 Ad-Hoc 签名，并在当前目录输出 **`AgentSpur.dmg`** 并自动在 Finder 中高亮选中。
4. 双击打开 `AgentSpur.dmg`，将 **AgentSpur** 拖入 **Applications（应用程序）** 文件夹即可启动！

### 方法 B：在终端 / iTerm2 中一行命令打包
```bash
chmod +x build_dmg.sh && ./build_dmg.sh
# 或使用 Makefile:
make dmg
```

---

## 包含的全部原生能力

- **五状态 15 FPS 原生动画**：内置「思考」「工作」「等你确认」「完成」「出错」五套 15 FPS CoreGraphics 矢量帧绘制，默认搭载明亮轻盈的 `Gin · 灵动微光` 冰瓷水滴角色。
- **菜单栏 Hover Tooltip**：鼠标悬停在菜单栏状态区时，自动展示当前最紧急的子任务名称、所属终端（`opencode TUI` / `iTerm2`）及实时状态持续时长。
- **严格遵循 `opencode.db` 只读解析**：
  - 使用 macOS 系统原生 `libsqlite3`（`SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX`）+ `FSEvents` 监听 `~/.local/share/opencode/opencode.db` 的 WAL 更新，绝不阻塞 `opencode TUI` 写入。
  - 自动按 `session.parent_id` 组装 Master 与子任务（`@explore` / `@general`），按 **待处理 / 运行中 / 已完成** 分组只读展示。
- **进入当前状态时长计时 & 状态切换自动归零**：每个主任务与子任务均实时显示 `正在思考 4s`、`正在工作 12s` 等等宽数字计时，状态切换时自动重置为 `0s`；已完成任务同步显示总执行耗时（`message.time.completed - created`）。
- **一键跳回终端 & 终端自动聚焦模式**：
  - 点击任意任务行，通过 `NSAppleScript` 激活并切换至对应的 `iTerm2` 标签页或 `opencode TUI` 窗口（不强行挪动桌面窗口位置）。
  - 开启「终端自动聚焦模式」后，检测到匹配特定 `opencode TUI` 或 `iTerm2` 标签页的子任务时自动高亮，并叠加 `CABasicAnimation` 天青呼吸闪烁聚焦边框。
- **额度直显与 `⌘R` 刷新**：支持点击面板右上角「额度Key」填入 `DEEPSEEK_API_KEY`（或通过环境变量传入）直连官方余额接口查询实时余额；未配置时自动离线汇总 `opencode.db` 本地累计开销。浮层内按 `⌘R` 即刻刷新。
- **静音完成提醒**：任务完成时通过 `UNUserNotificationCenter` 发送 `sound = nil` 的静音通知横幅，底部开关可随时关闭。
- **DeepSeek 角色包导入**：内置 5 款轻量角色，点击底部「导入角色包」可通过原生 `NSOpenPanel` 导入自定义 12×12 点阵 `.json` 角色包（示例见 `Resources/sample-deepseek-pack.json`）。
- **纯 CoreGraphics 本周效率折线图**：浮层底部原生绘制最近 7 天的吞吐效率（项/时）与平均耗时（秒）平滑折线图。

---

## 原生工程目录结构

```text
AgentSpur/
├── Package.swift                      # Swift Package 配置 (macOS 14+, AppKit + SQLite3)
├── build_dmg.sh                       # 零第三方依赖一键编译打包 AgentSpur.dmg 脚本
├── 双击打包DMG.command                 # Finder 双击自动打包脚本
├── Makefile                           # make dmg / make run / make clean
├── Resources/
│   ├── Info.plist                     # LSUIElement=true 纯菜单栏应用配置与 AppleEvents 声明
│   └── sample-deepseek-pack.json      # 示例自定义 DeepSeek 12x12 点阵角色包
└── Sources/
    └── AgentSpur/
        ├── main.swift                 # 应用入口、15 FPS 状态栏循环、FSEvents 与静音通知
        ├── Models.swift               # 五状态定义、计时格式化、自动聚焦规则与角色模型
        ├── OpenCodeDBReader.swift     # opencode.db SQLite WAL 只读查询与 7 日效率聚合
        ├── SpriteRenderer.swift       # CoreGraphics 15 FPS 角色渲染与 1024px AppIcon 生成器
        ├── TerminalBridge.swift       # iTerm2 / opencode TUI 标签跳转与前台窗口检测
        └── PopoverViews.swift         # 明亮浅色毛玻璃 NSPopover、闪烁聚焦边框与原生折线图
```
