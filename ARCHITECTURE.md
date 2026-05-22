# Enchron 架构

Purpose: 定义 Enchron 的稳定架构边界。
Status: Active architecture constitution.
Owner/scope: 模块职责、依赖方向、跨模块不变量、deliberate absences。
This file is not a phase summary, changelog, issue archive, implementation guide, or UI spec.

## 产品形态

Enchron 是面向 visionOS 的原生沉浸式视频播放器。用户从本地或远程来源选择媒体；应用把播放请求收敛到统一启动路径；`PlaybackCore` 报告媒体事实和播放状态；`PlayerUI` 决定呈现模式；`SpatialScene` 承担沉浸和全景呈现；`Persistence` 保存进度、偏好、凭证和场景状态。

主链路是：

`FileBrowsing -> PlaybackLaunchCoordinator -> PlaybackCore -> PlayerUI -> SpatialScene / Persistence`

两个边界最重要：

- 播放启动统一经过 `PlaybackLaunchCoordinator`。
- 播放模式属于 `PlayerUI` 决策。`PlaybackCore` 报告事实，不决定窗口、沉浸场景或全景呈现。

## 限界上下文

### PlaybackCore

负责媒体加载、播放控制、解码、状态、轨道、帧输出和媒体画像报告。它可以定义多个后端 adapter 实现，但不负责 app 组装或 UI 呈现。

关键边界包括 `PlaybackSession`、`PlaybackControlling`、`FrameOutput`、`MediaProfileDetecting`，以及 `MPVPlayerAdapter` 这类后端 adapter。

### PlayerUI

负责用户可见的播放控件、播放模式决策、时间轴行为、手势消歧和面向用户的能力状态。

`PlayerUI` 只消费共享播放语义和领域模型。它不能直接控制 mpv、Apple AV、SMB、WebDAV 或具体 adapter 生命周期。

### FileBrowsing

负责把本地、SMB、WebDAV、Photos 和未来来源统一成内部可浏览模型，决定哪些条目可作为媒体选择，并把它们转换成播放启动请求。

第三方协议 API 必须留在 FileBrowsing adapters 后面。

### SpatialScene

负责沉浸空间、虚拟屏幕、全景几何、场景选择和空间呈现概念。它的生命周期独立于当前是否正在播放。

### Persistence

负责持久化进度、偏好、凭证、数据源记录和屏幕位置。它只存取数据，不决定业务行为，也不触发播放、渲染或导航。

### App

负责 app 启动、scene wiring、导航壳层、依赖组装和播放启动协调。跨模块 adapter 构造与注入属于这里或等价的 composition code。

### Settings

负责设置界面。它通过 Persistence ports 读写数据，不发明存储行为。

### Shared

只承接低层、稳定、没有更明确业务归属的工具能力，例如 design tokens、Metal texture helpers、常量和窄扩展。它不是跨模块业务逻辑收容所。

## 依赖规则

- 依赖方向向内：`Adapters -> UseCases -> Domain`。
- 模块之间默认通过 Swift protocol 通信。
- 业务模块不能偷偷构造跨模块 adapter。
- `PlaybackCore` 可以报告当前媒体、位置、帧、轨道和媒体事实，但不能决定呈现模式或 UI 形态。
- `PlayerUI` 可以决定控件与播放模式，但不能操纵具体播放、网络或持久化 adapter。
- `SpatialScene` 渲染空间呈现并报告空间状态，不承接非空间播放控制。
- `Persistence` 存储数据，不解释产品行为。
- `Shared` 不能吸收有明确限界上下文归属的逻辑。

## 架构不变量

### Global

- 系统没有默认全局事件总线。
- 系统没有绕过 protocol 边界的默认路径。
- `Shared` 没有成为业务逻辑收容所的合法路径。

### PlaybackCore

- `PlaybackCore` 不切换窗口、沉浸场景或全景模式。
- `PlaybackCore` Domain 不 import UI、场景、SMB/WebDAV UI 或具体平台呈现层。
- 一个 `PlaybackSession` 同一时刻只服务一个媒体会话。切换媒体意味着结束旧会话并开始新会话。
- `PlaybackCore` 不能把 SDR 包装成 HDR，不能伪造 HDR 证据，不能暴露虚假的 dynamic tone mapping 声明。

### Playback Engine Routing

- `PlaybackCore` 可以定义多个后端 adapter 实现。
- Adapter 构造和 session 注入属于 `App` / composition code。
- `PlaybackLaunchCoordinator` 仍然是 direct playback 和 prepare/confirm playback 的唯一启动协调路径。
- 一个播放 session 只能拥有一个选定的 `PlaybackEngine`。
- Engine selection 必须发生在用户可见播放开始前。
- 一个 session 不允许并行播放引擎。
- 不允许双产品状态机。
- 不允许 session 运行中切换 engine。
- `PlayerUI` 不能按 mpv vs `appleAV` 这种具体 engine identity 分支。
- `PlaybackEngineRoute` 不是 `PlaybackMode`。
- `PlaybackMode` 仍然是呈现决策：窗口、沉浸场景或全景。
- `MediaProfile` 和共享 domain capability models 仍然是 UI 可见真相层。

### PlayerUI

- `PlayerUI` 拥有播放模式决策入口。
- `PlaybackCore` 和 `SpatialScene` 不拥有播放模式决策入口。
- `PlayerUI` 不直接控制具体播放引擎或远程协议 adapter。
- 统一时间轴、精确时间标签和逐帧步进是核心交互资产。削弱它们的改动是退化。

### FileBrowsing

- `FileBrowsing` 把不同来源转换成内部可浏览模型。
- 外层不直接消费第三方协议 API。
- 主浏览路径不暴露不可播放格式作为用户可选项。
- 凭证与连接身份不能依赖临时 UI 状态拼接出的漂移 key。

### SpatialScene

- 场景生命周期独立于播放生命周期。
- `SpatialScene` 是独立上下文，不是 `PlayerUI` 的实现细节。
- `SpatialScene` 不承接非空间播放控制逻辑。

### Persistence

- `Persistence` 不做业务决策。
- 凭证不存入 `UserDefaults`。
- `Persistence` 不触发播放、渲染或导航。

### App

- 系统不存在绕开 `PlaybackLaunchCoordinator` 的合法播放启动路径。
- `App` 负责组装，不承载各限界上下文内部的长期规则。
- 沉浸空间生命周期经过 `appModel.immersiveSpaceRequest` 和 `MainView` handler。调用点不能绕开这条路线独立控制 `openImmersiveSpace` / `dismissImmersiveSpace`。

## 跨模块关注点

### Playback Mode

播放模式包括窗口、沉浸场景和全景。决策属于 `PlayerUI`，事实来自各自拥有者：

- 投影和立体事实来自 `PlaybackCore`。
- 场景状态来自 `SpatialScene`。
- 当前 app 环境来自 `App` / `PlayerUI`。

规则是：决策在 UI，事实在拥有它的上下文。

### Contracts

Active normative contracts live in `docs/contracts/`.

Current active contracts:

- `docs/contracts/playback-engine-routing.md`

Do not link to contract files that do not exist. Do not create contract documents unless they constrain current or planned implementation boundaries.

### Ubiquitous Language

代码和文档使用 `docs/ubiquitous_language.md` 中的词汇。新术语成为架构词汇前，先更新该文件。

### Verification

自动化检查守逻辑、结构和 contract。visionOS 交互、HDR、空间呈现和性能仍然需要 Simulator 或真机验证，取决于改动触及的表面。

编译通过不等于体验正确。

## Deliberate Absences

除非未来架构决策显式引入，否则以下东西不存在：

- 没有全局事件总线。
- 没有中转 SMB / WebDAV 的后端服务。
- 没有绕开 `PlaybackLaunchCoordinator` 的第二播放启动路径。
- 没有藏在 SwiftUI `View` body 里的产品状态机。
- 没有 UI-level adapter selection between mpv and Apple AV。
- 没有把并行播放路线作为正常 session 模型。
- 没有把 `Shared` 当成跨模块业务容器。
- 没有可以替代 visionOS 人类/设备验证的自动化 UI 测试。
- 没有为了窗口模式捷径而牺牲沉浸场景演进的架构决策。

## 阅读顺序

1. 读本文，确认架构边界。
2. 读 `docs/product_philosophy.md`，确认产品优先级。
3. 读 `docs/ubiquitous_language.md`，确认共享术语。
4. 变更受 contract 约束的边界时，读 `docs/contracts/` 下的 active contract。
5. 根据触及表面读取就近 `AGENTS.md`、DesignPreview 文档和 visionOS reference。

归档 phase、QA、investigation 文档是历史上下文。它们与本文、当前源码或 active contracts 冲突时，先修正 active source of truth。
