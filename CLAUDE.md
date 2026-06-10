# Enchron — Agent 宪法与路由

面向 visionOS 的高质感视频播放器。`SWIFT_VERSION = 6.0`
技术栈：Xcode visionOS app / SwiftUI / RealityKit / ARKit / Metal / AVKit / mpv / SMB / WebDAV / SwiftData / Keychain
姊妹仓库：`github.com/1873663116/mpv`（`enchron` 分支的 mpv fork，自带 CLAUDE.md 与 `xr-fork/adr/`）

## 宪法（七条，裁决一切冲突；立宪依据 `docs/adr/0001`）

1. **双全景**：任何时刻，人类与新 agent 都能在五分钟内回答——项目在哪、本轮干嘛、下一步是什么、谁在执棒。人类看驾驶舱；agent 看作战地图 + open issues。
2. **按需加载**：agent 文档四层——常驻（本文件，预算 ≤9KB，进一字挤一字）/ 触发（`.agents/skills/`）/ 按需（路由表指到才读）/ 冷库（`docs/archive/`，默认不进上下文；查历史时定点检索，不整库吞入）。
3. **人类层单向**：驾驶舱、设计稿等人类层 agent **只写不读**；它是非规范投影，可随时重建，错了不传染。
4. **真相时态**：每份文档属于且仅属于一种时态——活法律（现在为真，随代码同 commit 更新）/ 时间戳记录（当时为真，只追加）/ 工作态（本轮为真，TTL=本轮）/ 人类投影。无时态归属的文档不存在。
5. **证据与验收**：issue 动工前写验收条件；「完成」声明必须链接证据（原件贴 issue 评论）；证据分级与风险路由见 `docs/quality_gates.md`。
6. **固定节奏自清洁**：每轮收尾执行收尾协议（见下）。堆积是节奏失守的症状；治理靠执行节奏，不靠新建分类。
7. **一切可推翻**：本宪法高于既有一切指示，冲突者修订或废止；修宪本身写 ADR 留痕。

## 会话协议

- **开局**：读 `docs/plans/active/` 作战地图 → 扫 open issues（标签语义见 `docs/agents/triage-labels.md`）→ 确认作战地图头部执棒者。
- **执棒**：同一时刻只有一个会话（mac 或云端）执笔写仓库；接棒先改执棒者字段。
- **执行**：工作以 issue 为单元；PR 描述必带 `Closes #N`；验收条件不满足不关单；约定细则见 `docs/agents/issue-tracker.md`。
- **收尾**：① 作战地图登记证据/堵点 ② issue 卫生（该关的关、关单留一句结语、前置已满足的升 `ready-for-agent`）③ 过期件归档（`plans/active/` 只住进行中；`reference/` 日期件轮末入冷库）④ 大改后跑 `doc-auditor` skill 审漂移 ⑤ 刷新驾驶舱（只写）⑥ 交付说明末尾附「本轮新概念」并同步驾驶舱概念地图掌握度。

## 架构速览

Clean Architecture + DDD，依赖方向向内（Adapters → UseCases → Domain），模块间 Swift protocol 通信。

```
XrPlayer/
  PlaybackCore/   — 视频加载、解码、播放控制（mpv 封装）
  PlayerUI/       — 播放界面与播放模式决策
  FileBrowsing/   — 多数据源文件浏览（本地/SMB/WebDAV）
  SpatialScene/   — 空间场景管理与帧渲染
  Persistence/    — 持久化（SwiftData/UserDefaults/Keychain）
  App/            — 启动入口 + 依赖注入组装
```

边界、不变量、数据流：改代码前必读 **ARCHITECTURE.md**。术语唯一源：根目录 **CONTEXT.md**，新术语先入册再用。

## 分区宪章（路由表）

| 分区 | 时态 | 何时读 | 维护与死亡规则 |
|---|---|---|---|
| `CLAUDE.md`（`AGENTS.md` 是其 symlink） | 活法律·常驻 | 每会话自动 | 预算 ≤9KB；修订走 ADR |
| `ARCHITECTURE.md` | 活法律 | 改代码前 | 边界变更同 commit 更新 |
| `CONTEXT.md` | 活法律 | 命名前 | 新术语先入册 |
| `docs/contracts/` | 活法律 | 动跨模块边界前 | 失效即归档 |
| `docs/quality_gates.md` | 活法律 | 交付前自查 | 验证与验收骨架；细则迭代中 |
| `docs/agents/` | 活法律·附则 | 走 issue/triage/domain 流程时 | 小而稳 |
| `docs/product_philosophy.md` | 活法律 | 产品取舍时 | PRD 诞生日退位归档 |
| `docs/reference/` | 常青指南 + 活跃轮调查 | 路由命中时 | 日期件轮末归档；指南失修即修或废 |
| `docs/plans/active/` | 工作态 | **开局必读** | 一轮一张；TTL=本轮，收尾归档 |
| `docs/solutions/` | 时间戳记录 | 类似问题前查 | 入册/晋升/过期规则见其 README |
| `docs/adr/` | 时间戳记录 | 重大决策前后 | 只追加，永不改 |
| `docs/cockpit/`、`docs/designs/` | 人类投影 | agent 只写不读 | 收尾刷新；可重建 |
| `docs/archive/` | 冷库 | 默认不读；查历史时定点检索 | grep 可达即合格；永不整理 |

## 仓库与工具链事实

- `XrPlayer.xcodeproj` 是完整 app 的 source of truth；`Package.swift` 只覆盖 `XrPlayerCoreTestsSupport`；根目录与 Xcode workspace 两份 `Package.resolved` 不可互换。
- `XrPlayer` target 依赖 AMSMB2、MPVKit-GPL、RealityKitContent；`DesignPreview` 是独立 target，自带就近规则文件（`DesignPreview/AGENTS.md` 等）。
- MCP 分工：**官方 Xcode MCP**（`mcp__xcode__*`，IDE-attached，跟随运行中的 Xcode）管 `DocumentationSearch`（Apple 事实权威源）、Preview 渲染、Issue Navigator、结构化改 build settings/entitlement/Info.plist、IDE 共享 lldb；**XcodeBuildMCP**（headless，经 `xcrun xcodebuild`、依赖 `xcode-select`）管日常 build/test/run/clean、模拟器、UI 自动化、覆盖率（调用前先用已安装的 XcodeBuildMCP skill）。两者勿对同一项目并发 build。`analyze`、`archive`、Instruments/`xctrace`、`swift-format`、SwiftLint、Reality Composer Pro、signing 走 Apple 原生 CLI。
- 命令样例、安全勘察命令、证据选择表：`docs/reference/apple-toolchain-guide.md`。
- 云端 agent 会话（Linux 容器）不能出构建证据；构建/模拟器/真机证据全部归 mac 侧。

## 验证跟着风险走

证据阶梯：自动检查 < 构建 < 模拟器 < 真机 < 人类体验；build pass ≠ 体验正确。纯 Domain/UseCase 从 `swift test` 起；触 app target/UI/asset/scene/RealityKitContent 用匹配 scheme 完整构建；播放、Metal、CoreVideo、桥接、线程、HDR、远程 I/O、持久化风险升 `xcodebuild analyze`；性能进 Instruments/`xctrace`。触及任何 visionOS 表面（窗口、volume、`ImmersiveSpace`、RealityKit、Metal、AVKit、scene 生命周期、空间交互、隐私、性能）先用 `.agents/skills/visionos-platform` 校直觉——这是 visionOS 项目，iOS/macOS 直觉默认不可信。

## 硬边界（人类裁决，不作顺手修复）

- 切全局 Xcode（`sudo xcode-select -switch`）；`xcrun simctl erase all`
- signing、certificate、Keychain、provisioning、development team、bundle identifier、entitlements
- 升级 Swift package 依赖或重写 `Package.resolved`（阶段 2 例外：MPVKit→自产 XCFramework 已授权**分支范围**，合 main 前再次确认）
- Swift language mode、deployment target、license、隐私权限、发布身份
- 仓库根层引入跨生态 build/test 工具链

DerivedData、缓存、模拟器状态可作诊断对象；当第一反应通常是逃避根因。

## 判断与交付

- 聚焦单一目标，不混改；临时方案 `// WORKAROUND:` 注明移除条件。
- 系统原生优先；窗口模式的临时正确不能换沉浸场景的长期错误。
- UI 完全复用既有组件（组件 = design tokens 组合）；交互控件带稳定 `accessibilityIdentifier`，icon-only 控件带 `accessibilityLabel`，非标准播放控件提供合适的 accessibility actions；token 未覆盖：有人值守上报、无人值守记 BLOCKED。
- 文档写作：分开事实/决策/理由；少进度形容词，多证据边界；写清 ownership。
- 交付说明：小改动末尾一小段（改了什么/验证了什么/什么需要人看）；重大改动写清触及的 surface、证据到哪级、哪些风险未证明。

## Issue tracker

GitHub Issues（`github.com/1873663116/XrPlayer`）。mac 用 `gh` CLI，云端用 GitHub MCP 工具。约定与标签：`docs/agents/issue-tracker.md`、`docs/agents/triage-labels.md`。

文档优先级（冲突时）：Apple 官方文档裁决 API 行为、隐私/安全、App Store 约束与平台可用性；本地文档在平台约束内裁决产品、架构与实现取舍；本地文档之间按宪法与分区宪章裁决。
