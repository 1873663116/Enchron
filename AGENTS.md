# Enchron — Agent 指令

面向 visionOS 的高质感视频播放器
技术栈：Xcode visionOS app project / Swift toolchain / SwiftUI / RealityKit / ARKit / Metal / AVKit / mpv / SMB / WebDAV / SwiftData / Keychain

`SWIFT_VERSION = 6.0`

Enchron 的目标是 Apple 平台原生品质——高质量的窗口播放、低学习成本、强沉浸感的full space
详见 `docs/product_philosophy.md`

---

## 架构速览

Clean Architecture + DDD，5 个限界上下文，依赖方向向内（Adapters → UseCases → Domain）。模块间通过 Swift protocol 通信。

```
XrPlayer/
  PlaybackCore/   — 视频加载、解码、播放控制（mpv 封装）
  PlayerUI/       — 播放界面与播放模式决策
  FileBrowsing/   — 多数据源文件浏览（本地/SMB/WebDAV）
  SpatialScene/   — 空间场景管理与帧渲染
  Persistence/    — 持久化服务（SwiftData/UserDefaults/Keychain）
  App/            — 启动入口 + 依赖注入组装
```

完整架构说明、Architecture Invariants、数据流图：**ARCHITECTURE.md**

---

## 仓库事实

- `XrPlayer.xcodeproj` 是完整 visionOS app 的 source of truth。
- `Package.swift` 定义 `XrPlayerCoreTestsSupport`，覆盖部分 core/library 测试，不是完整 app manifest。
- 根目录 `Package.resolved` 与 `XrPlayer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` 不可互换。
- `XrPlayer` target 依赖 AMSMB2、MPVKit-GPL 和 RealityKitContent。
- `DesignPreview` 是独立 Xcode target，局部规范入口是 `DesignPreview/AGENTS.md`。
- `.mcp.json` 配置 XcodeBuildMCP；MCP 是模拟器 UI、截图、accessibility、IDE 自动化补充层，不替代 CLI。

---

## Apple 工具链公理

- Apple 原生命令行是 Enchron 的构建、验证、分析和归档主线。
- `xcodebuild` 用于 app build、test、analyze、archive，以及查询 scheme、destination 和 build settings。
- `swift` / SwiftPM 只证明 `Package.swift` 覆盖的 package 逻辑。
- `xcode-select --print-path` 用于检查当前 Xcode；`xcrun` 按当前 Xcode/SDK 调用 Apple 开发工具。
- Simulator 与 destination 先用 `xcrun simctl` 和 `xcodebuild -showdestinations` 确认。
- `swift-format` 只处理格式一致性；大规模格式化必须单独成事。
- SwiftLint 是少量高信号架构守卫，不是架构设计器。
- `xcodebuild analyze` 用于静态分析；播放器、Metal、CoreVideo、bridging、线程和 adapter 改动时优先级升高。
- LLDB 用于运行时现场：断点、调用栈、线程、变量和崩溃。
- Instruments / `xctrace` 用于性能事实：启动、掉帧、CPU/GPU、内存和泄漏。
- Reality Composer Pro 属于空间内容生产链；RealityKit 问题同时检查资源、entity 层级、材质、坐标、scale、anchor、加载路径和 scene lifecycle。
- 仓库脚本若存在，先读脚本再运行；脚本应包裹 Apple 原生工具，而不是替代 Apple 工具链。

---

## 工作方式

把自己当作新加入项目的高级工程师：先理解系统边界，再选择工具和改动点。不要为了完成流程而忘记判断。

Agent 的职责是做出可解释的工程判断，不是完成文档流程。先确认 ownership、visionOS surface、产品边界和证据路径；只读取能改变当前判断的最小文档集合。能清楚说明某文档与当前任务无关，就可以不读它。硬边界、人类裁决项和架构不变量不能被效率理由绕过。

开始前持续持有三个问题：

- 这件事属于哪个限界上下文：PlaybackCore、PlayerUI、FileBrowsing、SpatialScene、Persistence、App、Settings、Shared、DesignPreview、docs / agents / contracts？
- 它触及哪个 visionOS surface：window、volume、`ImmersiveSpace`、RealityKit scene、AVKit/system video、mpv/Metal texture、Compositor Services、file/network/persistence、Simulator/device/performance？
- 什么证据能证明它真的变好了：`swift test`、`xcodebuild`、SwiftLint、`xcodebuild analyze`、Simulator、Vision Pro device、LLDB、Instruments / `xctrace`，还是人类体验判断？

代码改动先读 `ARCHITECTURE.md`，确认职责归属和 Architecture Invariants。触及 SwiftUI、RealityKit、ARKit、Metal、AVKit、scene/window lifecycle、spatial interaction、文件/网络/持久化、性能，或任何 iOS/macOS 平台假设时，使用 `.agents/skills/visionos-platform/SKILL.md` 找到最小相关 reference；不要一次性吞下所有平台文档。

UI / Design Preview 改动先读就近规范；当前入口是 `DesignPreview/AGENTS.md`。产品体验判断先读 `docs/product_philosophy.md`。

跨模块、跨文档、高风险、发布相关、架构 / contract / platform surface 变化，或需要多人、多轮接力的任务，写短计划。计划保存目标、边界、关键决策、未知项和当前有效证据；普通改动不写计划。

稳定接口、active contract 或跨模块边界发生变化时，先更新 `docs/contracts/` 和 `ARCHITECTURE.md` 的相关不变量，再改代码；接口和文档不同步时，后来的 agent 会在错误地图上工作。探索性 spike、局部 adapter 签名整理、方向尚未证明的改动，不先制造 contract 承诺；等边界成立后再文档化。

验证跟着风险走：纯 Domain / UseCase 改动通常从 `swift test` 开始；完整 app、UI、asset、target membership、RealityKitContent、signing、entitlement 或 bundle 改动用匹配 scheme 的 `xcodebuild`；播放器、Metal、CoreVideo、bridging、线程、HDR、远程 I/O 或持久化风险升高时考虑 `xcodebuild analyze`；性能和长时间观看问题进入 Instruments / `xctrace`。

---

## 判断提醒

- 先读真实上下文再动手：本文件、`ARCHITECTURE.md`、相关 skill/reference、就近 `AGENTS.md` 或专项文档。
- 系统原生优先：系统容器、材质、动效是第一选择；自定义需要改善核心体验。
- 聚焦单一目标：不要把修 bug、换风格、重构和工具链清理混成一团。
- 临时方案写清移除条件：`// WORKAROUND:` 后面要说明什么时候可以删。
- 交付要有证据：自动检查、结构守卫、smoke、Simulator/Canvas 或人类体验边界，选能证明问题的那一个。
- 沉浸场景持续在场：窗口模式下的临时正确，不能换来沉浸场景的长期错误。

---

## 需要人类裁决的边界

这些动作改变开发身份、全局环境、发布资格或长期架构，不作为顺手修复：

- 切换全局 Xcode：`sudo xcode-select -switch`
- 清空所有模拟器：`xcrun simctl erase all`
- 修改 signing、certificate、Keychain、provisioning profile、development team、bundle identifier 或 entitlements
- 升级 Swift package 依赖或随意重写 `Package.resolved`
- 顺手改变 Swift language mode、deployment target、license、隐私权限或发布身份
- 在仓库根层引入跨生态 app build/test 工具链

DerivedData、缓存和 Simulator 状态可以成为诊断对象；把它们当作第一反应通常是在逃避根因。

---

## 交付说明

小改动在最终回复末尾用一小段说明：改了什么、验证了什么、什么还需要人类看。不要给普通改动套模板。

重大、跨模块、高风险、发布相关或影响架构/合同/platform surface 的改动，需要结构化说明。重点不是字段齐全，而是让接手者知道：动了哪个 surface，读了哪些权威材料，证据到哪里为止，哪些体验、设备、HDR、性能、签名、隐私、license 或 fallback 风险还没有被证明。

---

## 文档语言

- 写清 ownership：谁拥有事实，谁拥有决策，谁只是执行。
- 分开事实、决策和理由；不要把调查材料写成项目规则。
- 少写进度形容词，多写证据边界；build pass、Simulator 正确、HDR 标签正确、窗口模式正确都不是完整正确性证据。
- 使用 `docs/ubiquitous_language.md` 术语：`PlaybackEngine` 不是 `PlaybackMode`；`PlaybackEngineRoute` 不是 presentation；`MediaProfile` 是共享事实层；`AppleNativeMedia` 需要证据；`OpenFormatMedia` 默认走 mpv-safe fallback。

---

## UI 编码约束

- UI 样式值（圆角、间距、动画、颜色、材质）优先通过 Design Token 表达；局部例外要能解释为什么不提升为 token。
- 需要 UI 测试定位的交互控件使用稳定 `accessibilityIdentifier`；
  icon-only / custom controls 使用明确 `accessibilityLabel`；标准文本控件保留正确的系统派生语义；
  非标准播放控件提供合适的 accessibility actions
- Token 未覆盖时：有人值守上报询问；无人值守任务记录 BLOCKED
- 涉及 UI 改动时，先读：**`.agents/skills/visionos-platform/SKILL.md`** 和就近 `AGENTS.md`

---

## 文档路由表

### 核心文档（改动代码必读）

| 文档 | 是什么 | 何时查阅 |
|------|--------|----------|
| **ARCHITECTURE.md** | 模块职责、数据流、Architecture Invariants、跨模块通信 | 任何代码改动前 |

### 产品与规范

| 文档 | 是什么 | 何时查阅 |
|------|--------|----------|
| `docs/product_philosophy.md` | 产品灵魂、三种播放模式的体验愿景 | 做设计决策时 |
| `docs/quality_gates.md` | 改动可信度与风险信号 | 提交代码前自查 |
| `docs/ubiquitous_language.md` | 项目统一术语表 | 命名类、方法、变量时 |
| `docs/reference/apple-toolchain-guide.md` | Apple 工具链命令与验证提示 | 构建、测试、分析、归档、发布前检查时 |

### docs/ 子目录

| 目录 | 是什么 | 何时查阅 |
|------|--------|----------|
| `docs/designs/` | HTML 设计稿与视觉原型 | 实现 UI 时对照设计 |
| `docs/reference/` | 技术调查报告（investigation）、构建指南 | 需要某领域的调查结论时 |
| `docs/solutions/best-practices/` | 经验沉淀：踩坑记录、架构模式、流程最佳实践 | 遇到类似问题时避免重蹈覆辙 |
| `docs/solutions/build-errors/` | 构建错误的诊断与修复方案 | 遇到构建报错时 |
| `docs/archive/` | 归档区：已完成的 ExecPlan、已解决的 issues、DDD 建模历史 | 需要历史上下文时 |

文档优先级（冲突时）：Apple 官方文档裁决 API 行为、隐私/安全、App Store 约束和平台可用性；本地文档在这些平台约束内裁决产品、架构和实现取舍。产品体验冲突按 product_philosophy > brainstorms/*-requirements > quality_gates > ARCHITECTURE > 其余。

---
