# AgentSpur (macOS 原生菜单栏应用)

**AgentSpur** 是一款纯原生 macOS `AppKit` 菜单栏 Agent 状态与费用精算监控工具（**无 WebView · 无 Electron · 无后端服务 · 无常驻守护进程**），专为 `opencode TUI` 与 `iTerm2` 打造，严格以 `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX` 只读方式解析本机 `~/.local/share/opencode/opencode.db`。

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

## 核心优化：今日只读极速架构、真实终端联动与汇率精算

1. **默认只展示今日使用情况（零全表扫描 · 零卡顿）**：
   - 借鉴开源社区（`tokscale` / `opencode` 原生索引设计）最佳实践，**绝不扫描庞大的 `part` 文本块表**，仅按 `message_session_idx` 与 `rowid` 逆序索引读取**今日（00:00 起）**活跃会话与消息元数据。
   - 全部 SQLite（`PRAGMA query_only = ON`）与终端探测均在后台低优先级队列防抖执行，浮层 15 FPS 动画原地更新 `NSImage` 帧而无需重建视图，无论历史 `opencode.db` 有多大均丝滑零延迟。
   - 动态通过 `PRAGMA table_info(session)` 适配 OpenCode `1.18+` 及各通道库（`opencode.db` / `opencode-stable.db` / `$OPENCODE_DB`），精准识别复用会话（`会话复用`）中 `time.completed IS NULL` 的实时思考/工作任务及子任务状态冒泡。

2. **100% 真实本机控制台探测（零假数据）**：
   - 自动探测本机当前真实打开的 **`Terminal.app` 标签页**、**`iTerm2` 标签页** 以及 **`tmux` 会话路径（`tmux list-panes`）**，通过工作目录（如 `~/ai-setup/opencode-master`）与会话标题自动配对。
   - 「终端自动聚焦」下拉菜单仅列出本机真实打开的终端窗口与「自动跟随当前前台终端窗口」，点击任务行即可直达对应真实标签页。

3. **DeepSeek 阶梯计费、线上公开汇率 API 与官方 CSV 对账**：
   - 接入线上直连公开汇率 API（`jsDelivr currency-api` + `open.er-api` + `Frankfurter` 三源自动容灾），支持一键切换 `¥CNY / $USD`。
   - 严格按北京时间（UTC+8）忙闲时（闲时 5 折）及 `deepseek-flash`（含 `DeepSeek-V4.1-Flash`）/ `deepseek-v4-pro` 官方阶梯单价逐笔精算今日 `input_cache_hit_tokens`、`input_cache_miss_tokens`、`output_tokens`、`request_count`，并支持导入官方 `amount-*.csv` / `cost-*.csv` 对账。

---

## 原生工程目录结构

```text
AgentSpur/
├── Package.swift                        # Swift Package 配置 (macOS 14+, AppKit + SQLite3)
├── build_dmg.sh                         # 零第三方依赖一键编译打包 AgentSpur.dmg 脚本
├── 双击打包DMG.command                   # Finder 双击自动打包脚本
├── Makefile                             # make dmg / make run / make clean
├── Resources/
│   ├── Info.plist                       # LSUIElement=true 纯菜单栏应用配置与 AppleEvents 声明
│   └── sample-deepseek-pack.json        # 示例自定义 DeepSeek 12x12 点阵角色包
└── Sources/
    └── AgentSpur/
        ├── AgentSpurApp.swift           # @main 应用入口、15 FPS 状态栏循环、实时汇率与静音通知
        ├── DeepSeekPricingEngine.swift  # UTC+8 忙闲时 5 折阶梯计费、实时 USD/CNY 汇率与官方 CSV 解析
        ├── Models.swift                 # 五状态定义、计费对账模型、计时格式化与角色模型
        ├── OpenCodeDBReader.swift       # opencode.db SQLite WAL 只读查询、逐笔 Token 精算与 7 日效率聚合
        ├── SpriteRenderer.swift         # CoreGraphics 15 FPS 角色渲染与 1024px AppIcon 生成器
        ├── TerminalBridge.swift         # iTerm2 / opencode TUI 标签跳转与前台窗口检测
        └── PopoverViews.swift           # 明亮浅色毛玻璃 NSPopover、精算参数卡片、闪烁聚焦边框与原生折线图
```
