# Enchron 架构

这份文档是给第一次进入 Enchron 的人类开发者和空白状态 Agent 看的
它回答三个问题：

1. 这个项目的主链路是什么
2. 某类需求或 bug 应该先去哪个模块、哪个入口看
3. 哪些边界是稳定的，不能因为一时方便被绕过

它不是 phase1~4 设计文档的摘要，也不是实现细节手册这里只记录高层结构、稳定职责、跨模块边界和故意不存在的东西具体实现细节、回归项、测试步骤分别看： `docs/design_docs/`、`REGRESSION.md`、`TESTING.md`


## Bird's Eye View

Enchron 是一个面向 visionOS 的原生沉浸式视频播放器用户从本地或远程数据源选择视频，应用统一走播放启动路径，播放核心负责加载与解码，界面层负责控件与播放模式决策，空间场景负责沉浸式呈现，持久化层负责保存进度、偏好和凭证

主链路可以用一句话概括：

`FileBrowsing -> PlaybackLaunchCoordinator -> PlaybackCore -> PlayerUI -> SpatialScene / Persistence`

其中有两个事实最重要：

- 播放启动路径必须统一无论入口来自文件浏览、播放列表还是未来的自动播放，最终都要收敛到 `PlaybackLaunchCoordinator`
- 播放模式决策属于 `PlayerUI``PlaybackCore` 只负责“能不能播、播到哪里、输出什么帧和元数据”，不负责决定窗口模式、沉浸场景模式还是全景模式

如果你是第一次看这个仓库，先把项目理解成 5 个业务上下文加 3 个支撑目录：

- `PlaybackCore`：播放与解码
- `PlayerUI`：播放界面与模式决策
- `FileBrowsing`：文件来源接入与浏览
- `SpatialScene`：沉浸式场景与空间呈现
- `Persistence`：进度、偏好、凭证等持久化
- `App`：组装、启动和导航壳层
- `Settings`：设置界面
- `Shared`：少量低层通用能力


## System Shape

### `PlaybackCore`

负责媒体加载、解码、播放控制、播放状态、媒体特征识别

这里是“播放器引擎”而不是“播放器界面”你应该在这里找到：

- `PlaybackSession`
- `PlaybackControlling`
- `FrameOutput`
- `MediaProfileDetecting`
- `MPVPlayerAdapter`

如果问题是“为什么这段视频播不出来”“暂停恢复后状态不对”“HDR 元数据是否可信”，先看这里

如果问题是“按钮怎么排”“当前应该切到什么播放模式”“详细时间轴怎么交互”，不要先改这里

### `PlayerUI`

负责用户看到和操作的播放界面，以及播放模式决策

这里包含：

- 播放控件，如 `PlayerControlsView`（含统一时间轴、精确时间标签、逐帧步进）
- 视频详情页，如 `VideoDetailView`（元数据展示、轨道选择、播放确认）
- 纯界面侧计算，如 `DetailedTimelineGeometry`
- 手势消歧与模式决策值对象

如果问题是”控件表现不对””时间轴交互退化””窗口/沉浸/全景切换规则有误”，先看这里

### `FileBrowsing`

负责把“本地文件、SMB、WebDAV”统一成可浏览、可选择、可交给播放启动器的文件来源

这里应该解决的是：

- 如何连接数据源
- 如何浏览目录
- 哪些文件可播放
- 如何把第三方协议库隔离在适配器层后面

如果问题是“连不上 SMB”“WebDAV 列表不对”“本地浏览器过滤规则不对”，先看这里

### `SpatialScene`

负责沉浸空间、场景选择和空间呈现相关能力

它当前既包含已落地入口，也包含未来会继续扩展的空间渲染能力读这个模块时要区分两类东西：

- 已存在并可用的入口，例如 `SceneSelectorView`、`ImmersiveSpaceView`
- 仍会继续沉淀的内部模型与渲染结构

如果问题是“沉浸空间怎么开关”“场景页怎么呈现”“未来虚拟屏幕应该挂在哪里”，先看这里

### `Persistence`

负责保存和读取持久化数据，但不负责决定业务行为

当前主要是四类 port：

- `ProgressStoring`
- `PreferencesStoring`
- `CredentialStoring`
- `ScreenPositionStoring`

如果问题是“记不住进度”“设置重启丢失”“SMB 凭证不稳定”，先看这里

### `App`

负责依赖注入、应用启动、导航壳层、播放启动协调

你应该把 `App` 理解为“组装区”和“入口区”，而不是业务实现区关键入口包括：

- `XrPlayerApp`
- `AppCoordinator`
- `PlaybackLaunchCoordinator`
- `MainView`

如果你不确定某个功能是从哪里被接到一起的，先从这里找

### `Settings`

负责设置界面本身它读取和写入 `Persistence` 提供的偏好 port，但不自己发明存储机制

### `Shared`

只放低层、跨模块、稳定且无明显业务归属的工具能力，例如图像缓冲与 Metal 纹理转换、常量、基础扩展

这里不是“想不到放哪就放哪”的目录


## Dependency Rules

这是本项目最重要的边界说明

- 依赖方向向内：`Adapters -> UseCases -> Domain`
- 模块之间默认通过 Swift protocol 通信，而不是直接依赖具体实现
- `App` 负责组装依赖；业务模块不自己偷偷 new 出跨模块 adapter
- `PlaybackCore` 可以告诉外界“当前媒体是什么、当前播放到哪里、当前输出了什么”，但不能决定界面长什么样
- `PlayerUI` 可以决定播放模式和控件状态，但不能直接操纵 mpv、SMB、WebDAV 这些底层实现
- `Persistence` 负责存和取，不负责解释业务含义，也不负责驱动 UI 状态
- `Shared` 不能吸收跨模块业务逻辑；如果某段代码有明确业务归属，就不应该放在 `Shared`


## Architecture Invariants

这里是各模块高稳定、跨阶段仍成立的边界，某些功能是被故意设置为“不存在”的

### Global

- 系统中不具备默认的全局事件总线作为模块通信机制
- 系统中不具备绕过 protocol 边界的默认跨模块调用约定
- `Shared` 中不具备承接任意业务逻辑的合法路径

### PlaybackCore

- `PlaybackCore` 不具备切换窗口 / 沉浸 / 全景播放模式的功能
- `PlaybackCore` 不直接依赖 SwiftUI、RealityKit、SMB/WebDAV UI 层
- `PlaybackCore` 的 `Domain` 层不具备 import UI / 场景 / 第三方协议框架的合法能力；允许范围由 SwiftLint 守卫
- 一个 `PlaybackSession` 同一时刻只服务一个媒体会话；切换媒体意味着结束旧会话并开始新会话
- `PlaybackCore` 不具备把 SDR 包装成 HDR、或为 HDR 生成错误 HDR 信息与 Dynamic Tone Mapping 标记的合法出口

### PlayerUI

- `PlayerUI` 具备播放模式决策入口；`PlaybackCore` 和 `SpatialScene` 不具备这个入口
- `PlayerUI` 不具备直接控制 mpv 或远程协议 adapter 的功能
- 统一时间轴（含精确时间标签和逐帧步进）是核心交互资产，为了高性能地实现这个功能，可以在一定程度上突破架构限制

### FileBrowsing

- `FileBrowsing` 负责把不同来源统一为内部可浏览模型；外层不具备直接消费第三方协议 API 的约定
- 主浏览路径不具备暴露不可播放格式作为用户可选项的功能
- 数据源凭证与连接信息不具备依赖临时 UI 状态拼接漂移 key 的合法实现方式

### SpatialScene

- 场景生命周期独立于当前是否正在播放
- `SpatialScene` 不具备作为 `PlayerUI` 子视图实现细节存在的定位，它是独立上下文
- `SpatialScene` 不具备承接非空间播放控制逻辑的职责

### Persistence

- `Persistence` 不具备业务决策功能
- 凭证存储不具备落在 `UserDefaults` 的合法实现
- `Persistence` 不具备直接触发播放、渲染或导航行为的职责

### App

- 系统中不存在绕开 `PlaybackLaunchCoordinator` 的合法播放启动路径
- `App` 负责组装，不具备承载各业务上下文内部长期规则的职责
- 系统中不存在绕开 `appModel.immersiveSpaceRequest` + MainView 处理器直接调用 `openImmersiveSpace` / `dismissImmersiveSpace` 的合法路径。`SceneSelectorView`、`ToggleImmersiveSpaceButton` 已迁移为 request 路由。所有沉浸空间生命周期管理统一在 MainView 的 `onChange(of: appModel.immersiveSpaceRequest)` 中处理。


## Cross-Cutting Concerns

### 播放模式决策

播放模式有三类：窗口、沉浸场景、全景判定属于 `PlayerUI`，但判定所需事实来自多个上下文：

- 视频投影类型来自 `PlaybackCore`
- 场景活跃状态来自 `SpatialScene`
- 当前 UI 环境来自 `App` / `PlayerUI`

这意味着“决策在 UI，事实在别处”

### 统一术语

代码命名应与 `docs/ubiquitous_language.md` 对齐最容易混淆的是：

- `MediaFile` 在 `FileBrowsing` 和 `PlaybackCore` 中不是同一个概念
- `DataSource` 是文件来源实体，`DataSourceConnecting` 是连接 port

### 前后端契约

本项目需要持续维护“前端”和“后端”之间的契约文档与 API 参考。

规范性边界、协作规则、变更策略看 `docs/contracts/frontend-backend-contract.md`。

具体接口、schema、错误结构和样例看 `docs/contracts/`。

凡是远程数据模型、字段语义、错误结构或交互流程发生变化，都应同步更新并维护 `docs/contracts/`，使契约与实现保持长期一致，而不是只在某次改动时临时补写。

### 测试与真机验证

自动化测试主要守纯逻辑、结构约束和契约；visionOS 交互、观感和流畅度依赖真机验证不要把“编译通过”误当成“体验已验证”


## Deliberate Absences

下面这些东西默认就是不存在的；如果要引入，必须先证明它们没有破坏本架构边界

- 没有全局事件总线
- 没有后端服务来中转 SMB / WebDAV
- 没有绕过 `PlaybackLaunchCoordinator` 的第二套播放启动主路径
- 没有把业务状态机默认塞进 SwiftUI `View`
- 没有把 `Shared` 当成跨模块业务收容所
- 没有自动化 UI 测试替代 visionOS 真机验证
- 没有为了窗口模式临时问题而牺牲沉浸场景未来演进的架构决策


## How To Read This With Other Docs

按下面顺序读最省时间：

1. 先读本文，建立心智地图和边界感
2. 再读 `docs/product_philosophy.md`，理解体验目标
3. 改代码前读 `REGRESSION.md`，知道这次改动会触发哪些回归项
4. 验证时读 `TESTING.md`，按双轨体系执行
5. 需要深入某个设计背景时，再进入 `docs/design_docs/phase1~4`

phase1~4 设计文档是历史设计与推演材料；本文是当前项目的高层事实表述两者冲突时，以本文和当前代码边界为准；如果本文失真，应先修本文，再继续扩展实现
