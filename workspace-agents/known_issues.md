# Enchron 已知问题

更新时间：2026-03-08

已归档并标记为已修复：

- [docs/archive/known_issues_2026-03-06_resolved.md](/Users/xiongzhipeng/Applications/XrPlayer/docs/archive/known_issues_2026-03-06_resolved.md)
- [docs/archive/known_issues_2026-03-08_resolved.md](/Users/xiongzhipeng/Applications/XrPlayer/docs/archive/known_issues_2026-03-08_resolved.md)

当前主文档仅保留仍开放的问题。

---

## KI-007：首个本地视频播放和首个 WebDAV 视频播放会出现长时间黑屏，重复打开则接近秒开

### 现象

- 冷启动 App 后，第一次打开任意本地视频时，会经历一段明显偏长的黑屏加载。
- 关闭该视频后，再打开另一个本地视频，或者重新打开同一个视频，通常都会接近秒开。
- 但如果切换到 WebDAV 服务器并第一次打开任意视频，又会再次出现一段明显偏长的黑屏等待。
- 一旦这个 WebDAV 播放链路“热起来”之后，再重复打开同类远程视频，等待时间又会明显缩短。

### 当前最高概率解释

这更像是**“首个播放链路冷启动成本被集中暴露”**，而不是某一个特定视频文件本身有问题。

更具体地说，当前现象高度符合两层冷启动叠加：

1. **播放器启动链路本身的冷启动**
- 首次播放时，仍然要经历 `waitForVideoLayerIfNeeded()`、`ensureMPVReady()`、首次 `loadfile`、首帧可见前的状态切换等一整套初始化路径。
- 虽然 `XrPlayerApp.swift` 已经在启动时调用了 `player.warmup()`，但 warmup 只能预热一部分 mpv 上下文；真正与具体媒体绑定的 demux / probe / 首帧准备仍然发生在第一次 `play(url:)`。
- 这解释了“第一次本地播放慢，第二次本地播放快”。

2. **远程 WebDAV 播放链路的独立冷启动**
- 对非文件 URL，`MPVPlayerAdapter.makeLoadRequest(for:)` 会直接把远程 URL 传给 mpv，而不是先转成一个已准备好的本地文件句柄。
- 这意味着第一次打开 WebDAV 视频时，除了播放器自身冷启动外，还要额外支付一整套远程源初始化成本：URL 解析、DNS/TCP/TLS、认证、HTTP/WebDAV 读流建立、首段数据探测和 demux 预读。
- 当同一个远程链路已经跑热后，连接、认证状态、服务器侧缓存和 mpv 内部状态更可能被复用，所以重复打开会明显更快。
- 这也解释了“本地播放已经热了，但第一次切到 WebDAV 仍然又慢一次”。

### 为什么会表现为“黑屏”而不是普通 loading

- 当前用户看到的等待窗口仍然主要发生在“文件已开始装载，但首帧尚未真正显示”这个阶段。
- 只要首帧还没 present，视频承载层本身就是黑底，因此冷启动成本会被用户感知成一段黑屏等待，而不是立即看到画面。

### 代码证据

- [XrPlayerApp.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/XrPlayerApp.swift#L96)
- [MPVPlayerAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift#L153)
- [MPVPlayerAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift#L172)
- [MPVPlayerAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift#L817)
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L414)

### 暂定修复方向

1. 补阶段耗时日志，把“首播本地”和“首播 WebDAV”拆成：layer ready、mpv ready、remote connection ready、loadfile、首帧显示几个阶段。
2. 区分“播放器冷启动预热”和“远程源冷启动预热”，避免本地 warmup 只解决了一半问题。
3. 为 WebDAV 首播单独评估更激进的首帧策略，例如连接预建立、认证预热、降低首次探测/预读等待。
4. 把 UI loading 的结束时机继续对齐到“首帧已可见”，避免用户把底层冷启动全感知为纯黑屏。

### 调查状态

- 状态：开放中
- 结论类型：现象与当前代码路径高度一致的高概率推断，尚待阶段耗时日志进一步定量确认

---

## KI-008：播放控件命中区和注视反馈不足，且 `±10s` 按钮视觉消失但功能仍可触发

### 现象

- 播放控件，尤其是二级进度条 / 精确时间轴中的多个可交互区域，实际可用的识别区域偏小，不容易被准确注视到。
- 即使用户已经把视线注视到可交互区域，界面也缺少足够明确的 hover / focus / highlight 反馈，用户很难确认“当前是否已经选中这个区域”。
- 主播放控件中的左右 `快退 10s / 快进 10s` 按钮在视觉上会消失，或者表现为几乎不可见。
- 但即使按钮看不见，对应的 `-10s / +10s` 跳转功能仍然可以正常触发。

### 当前最高概率解释

这更像是**可交互尺寸、视觉反馈和符号渲染样式三个层面同时偏弱**，而不是单一的逻辑 bug。

#### 1. 二级时间轴的实际命中区偏保守

- `DetailedTimelineView` 中，时间带本体虽然有整块拖拽手势，但其它重要控件仍主要依赖较小尺寸的 button / slider 默认命中区。
- 例如关闭按钮使用 `44x44`，逐帧按钮使用 `56x56`，在 visionOS 的注视交互里偏保守，尤其放在复杂玻璃背景之上时更容易出现“能用但难对准”的体验。

#### 2. 二级时间轴缺少显式的 focus / hover 状态反馈

- 当前精确时间轴主要依赖默认 `buttonStyle(.plain)` 和系统默认 Slider 外观。
- 代码里没有为时间带、缩放条、逐帧按钮、关闭按钮提供单独的 focus ring、hover 高亮、缩放、发光或材质变化。
- 因此即使用户已经注视到目标区域，也没有足够强的视觉确认信号。

#### 3. `±10s` 按钮更可能是“视觉样式丢失”，不是“控件不存在”

- `PlayerControlsView` 里的两个按钮仍然在，且 `videoViewModel.skip(by: -10)` / `skip(by: 10)` 仍然绑定在点击动作上。
- 这与“功能还能正常触发”完全一致，说明问题大概率不在事件绑定，而在视觉呈现。
- 当前这两个按钮使用 `.buttonStyle(.plain)`，图标也没有额外设置 `foregroundStyle`、背景或选中态；在当前 glass 背景、材质和层级关系下，符号可能与背景亮度过于接近，从而看起来像“消失”。

### 代码证据

- [PlayerControlsView.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/PlayerUI/Views/PlayerControlsView.swift#L136)
- [PlayerControlsView.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/PlayerUI/Views/PlayerControlsView.swift#L166)
- [DetailedTimelineView.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/PlayerUI/Views/DetailedTimelineView.swift#L73)
- [DetailedTimelineView.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/PlayerUI/Views/DetailedTimelineView.swift#L185)
- [DetailedTimelineView.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/PlayerUI/Views/DetailedTimelineView.swift#L214)

### 暂定修复方向

1. 放大二级时间轴内关键交互元素的 hit target，包括关闭按钮、逐帧按钮、缩放条和时间带边缘的可拖拽缓冲区。
2. 为二级时间轴内所有关键区域补充明确的注视反馈，例如 hover 高亮、边框、发光、轻微缩放或材质变化。
3. 为 `±10s` 按钮补上稳定的视觉载体，例如固定前景色、圆形底板、选中态 / hover 态和更强对比度，避免在 glass 背景中丢失。
4. 在 visionOS Simulator 和真机上分别复测“能否容易注视到”和“注视后是否能立即看出已命中”。

### 调查状态

- 状态：开放中
- 结论类型：基于当前 UI 实现与用户现象的一致性推断，尚待后续交互回归验证

## 二级时间轴的UX问题

首先是随着时间阈值的放大，二级时间轴的时间精度没有随着变化，刻度也变化也不足。缩放时间阈值，时间轴的逻辑也有问题。目前的实现逻辑是在圆角矩形内内置了一个时间轴，所以用户在左右拖动时，拉动的只是圆角矩形内的时间轴，但实际需要的只是在圆角矩形内内置时间会随着阈值放大缩小而变化的时间刻度。因为圆角矩形就是时间轴本身，所以用户往左右拖动是直接拉动整个圆角矩形运动的。
其次，而时间阈值的拖动并不是无极调节的，目前这种交互方式是比较反直觉的，这点也需要改变。

### 疑问
拉动二级时间轴的时候，能否实现画面实时随着拖动而同步变化，如果能够实现，性能消耗如何，希望有一个平衡性能和这种交互流畅性的体验


## HDR10和杜比视界格式能够识别，但无法正确生效，实际观感为SDR

---


## 2026-03-09 Referee 裁定：争议 Bug 复核

以下条目保留了 **Bug Finder 原始字段**，并补充 Referee 的最终判断。

### Bug 3：SMB 连接模型与真实用户场景不匹配：当前要求地址里包含 share name，导致“只填 IP + 用户名密码”的常见 NAS/SMB 用法无法连接

#### Bug Finder 原始条目
- **影响**：用户在真机上即使输入正确的服务器 IP、用户名、密码，也可能仍然无法连接 SMB。
- **原始证据**：
  - `XrPlayer/FileBrowsing/Domain/ValueObjects/ConnectionInfo.swift:35-41`：SMB 地址若不包含 share name，会直接抛 `missingSMBShare`
  - `XrPlayer/FileBrowsing/Domain/ValueObjects/ConnectionInfo.swift:103-114`：错误文案明确要求 `smb://ip/share`
  - `XrPlayer/FileBrowsing/Views/DataSourceConfigView.swift:17-21`：UI 占位文案也要求用户输入 `smb://192.168.1.20/share`
  - 用户于 **2026-03-09** 提供真机实测：XrPlayer 当前 SMB 无法连接；而其它播放器/文件管理器只填写 **服务器 IP + 用户名 + 密码** 即可成功连接
- **原始判断**：当前实现把“必须先知道并手动填 share 名”当成前提，这与很多 SMB 客户端常见的“先连服务器，再浏览 share 列表”工作流不一致，因此会直接挡住一类真实可连的服务器。
- **原始复现/验证步骤**：在真机上新增 SMB 数据源时仅输入服务器 IP、用户名、密码（可选）；当前实现会在地址解析阶段或后续连接阶段失败。

#### Referee 裁定
- **最终裁定**：Reduced
- **决定性证据**：`ConnectionInfo.remote(...)`、`DataSourceConfigView`、`V03Tests.testRemoteSMBAddressParsingRequiresShareName` 一起把 `smb://ip/share` 固化成了当前实现契约。
- **简要解释**：Bug Finder 描述的用户痛点是真实的，但从代码、UI 和测试看，这更像**当前产品边界 / UX 缺口**，而不是“实现违背自身规格”的 defect，因此需要降级。

### Bug 6：HDR 识别与实际输出存在明显不一致：两条渲染路径都可能把 HDR 观感降成 SDR / 错色

#### Bug Finder 原始条目
- **影响**：HDR 标签可信度受损；用户会看到“识别出 HDR，但看起来像 SDR 或色彩不对”。
- **原始证据（原生 GPU 路径）**：
  - `XrPlayer/Shared/MPVNativeMetalLayerView.swift:61-67`：输出层固定 `metalLayer.pixelFormat = .bgra8Unorm`
- **原始证据（software/fallback 路径）**：
  - `XrPlayer/Shared/MetalVideoRenderer.swift:88-95, 105-117, 173-184`：10-bit 帧只靠 `isHDR10Bit` 切换 10-bit drawable 与 BT.2020 矩阵
  - `XrPlayer/Shared/VideoShaders.metal:34-44`：shader 直接做 SDR 风格的 YUV→RGB 线性矩阵转换，未处理 PQ/HLG EOTF；并对 full-range/10-bit 仍使用固定 `0.0625` 偏移
- **原始判断**：无论走 native 还是 fallback，当前代码都没有形成一条“可证明正确”的 HDR 输出链路。
- **原始复现/验证步骤**：播放 HDR10 / Dolby Vision / full-range 素材，对比高光、暗部与色域；可重点观察“像 SDR”“黑位抬高”“高光被压平”等现象。

#### Referee 裁定
- **最终裁定**：Reduced
- **决定性证据**：fallback 链路里 `VideoShaders.metal` 只有固定矩阵 YUV→RGB 变换，没有 PQ/HLG EOTF；`MetalVideoRenderer` 也主要依据 `10-bit video-range` 切换 HDR 相关输出。与此同时，native GPU 路径仍显式开启 `target-trc/prim=auto` 与 `wantsExtendedDynamicRangeContent`。
- **简要解释**：fallback HDR 正确性缺陷证据很强；但 native GPU 路径目前更像**高风险疑点**，尚不足以静态证明为普遍错误输出。所以应从“两条链路都已坐实有问题”降级为“fallback 问题明确，native 链路仍需真机确认”。

### Bug 7：播放列表绕过统一播放启动闸门，失败时会留下错误的“正在播放”UI 状态

#### Bug Finder 原始条目
- **影响**：用户会看到播放窗口/状态残留，但实际播放失败。
- **原始证据**：
  - `XrPlayer/XrPlayerApp.swift:48-91`：主入口 `beginPlayback(for:)` 会做取消旧任务、等待 layer、失败回滚 `appModel.stopPlayback()`
  - `XrPlayer/PlayerUI/Views/PlaylistView.swift:39-44`：Playlist 直接 `appModel.startPlayback(url:)` + `try? await videoViewModel.play(url:)`
  - `try?` 会吞掉外层错误，失败后不会执行统一回滚
- **原始判断**：Playlist 是一条旁路启动链路，错误处理和 UI 状态恢复都与主入口不一致。
- **原始复现/验证步骤**：让 Playlist 中某项播放失败（远程鉴权失败、无效 URL 等），观察失败后窗口播放 UI 是否仍保持激活。

#### Referee 裁定
- **最终裁定**：Accepted
- **决定性证据**：`PlaylistView` 直接调用 `appModel.startPlayback(url:)`；`MainView` 只要 `appModel.isPlaying` 为真就会继续展示播放窗口；而失败时清理 `appModel.stopPlayback()` 的统一回滚只存在于 `XrPlayerApp.beginPlayback(for:)`。
- **简要解释**：即使 `WindowVideoViewModel` 会设置 `lastErrorMessage` 并弹出错误 Alert，Playlist 仍绕过了统一回滚链路，所以“失败后遗留错误播放态 UI”这一核心指控成立。

### Bug 10：持久化适配器仍是 `fatalError("TODO: implement")`，一旦接入就是确定性崩溃

#### Bug Finder 原始条目
- **影响**：当前属于潜伏炸点；未来一旦接线就会在运行期直接崩溃。
- **原始证据**：
  - `XrPlayer/Persistence/Adapters/UserDefaultsStore.swift:6-12`
  - `XrPlayer/Persistence/Adapters/SwiftDataStore.swift:6-36`
- **原始判断**：不是编译错误，但属于明确的运行期 crash point。
- **原始复现/验证步骤**：任何地方实例化并调用这些方法，程序都会立刻崩溃。

#### Referee 裁定
- **最终裁定**：Accepted
- **决定性证据**：`UserDefaultsStore` 与 `SwiftDataStore` 的对外方法当前全部是 `fatalError("TODO: implement")`；仓库搜索也未发现现有调用点，这与原报告“潜伏炸点，一旦接入即崩”的表述完全一致。
- **简要解释**：这不是当前主线路径上的已触发 bug，但 Bug Finder 原本就把它定义为低优先级潜伏问题；按这个口径，结论成立。

### Bug 11：`MediaFolder.dataSourceID` 每次 listing 都随机生成，不稳定且不语义正确

#### Bug Finder 原始条目
- **影响**：如果后续依赖该字段做导航、缓存、持久化或 UI 识别，会出现同一文件夹“身份漂移”。
- **原始证据**：
  - `XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift:127-131`
  - `XrPlayer/FileBrowsing/Adapters/Local/LocalDataSourceAdapter.swift:70-74`
  - `XrPlayer/FileBrowsing/Adapters/SMB/SMBDataSourceAdapter.swift:147-151`
- **原始判断**：字段名叫 `dataSourceID`，但实际返回随机 UUID，不是数据源真实 ID。
- **原始复现/验证步骤**：对同一路径多次刷新 listing，若后续有依赖该字段的逻辑，将看到同一 folder 身份不稳定。

#### Referee 裁定
- **最终裁定**：Reduced
- **决定性证据**：Local / WebDAV / SMB 三个适配器都在构造 `MediaFolder` 时写入 `dataSourceID: UUID()`；但当前仓库中几乎没有运行逻辑消费 `.dataSourceID`，现有 UI/逻辑主要依赖 `id` 与 `path`。
- **简要解释**：这个字段的赋值语义确实不稳，但现阶段更接近**建模/命名债务**，还没有形成已观测到的功能错误，因此需要降级处理。

### 最终汇总
- **Accepted**：1、2、4、5、7、8、9、10
- **Reduced**：3、6、11
- **Rejected**：无


## 用户新增

MainView UI无法使用apple原生的用户自由缩放窗口的手势，播放时，播放窗口也无法随着视频的分辨率比例自动调整窗口比例。
但目前在播放时窗口的边框带有的Liquid glass非常美丽，但我希望能将边框再缩窄一些，但不要消除边框。


---

## 2026-03-09 Referee 裁定：Phase 文档硬约束审计新增问题

以下条目保留了 **Bug Finder 原始字段**，并补充 Referee 的最终裁定，可直接独立阅读。

### DOC-001：Phase 4 把“虚拟场景播放必须纳入 v1.0”写成硬要求，直接冲突于 Requirements 的 MVP 边界

#### Bug Finder 原始条目
- **影响与得分**：严重（+10）—— 如果直接落成编译级硬约束，会把上位需求文档明确标成“MVP 可缺省”的能力，错误提升为硬门槛。
- **原始判断**：文档层级/优先级错误；文档错误；`v1.0 必须包含虚拟场景播放能力` 在修正文档前绝对不能写进硬约束 YAML。
- **原始证据**：
  - `workspace-agents/Requirements.md:73-75,79-100`
  - `workspace-agents/design_docs/phase4_implementation_roadmap.md:177-199`
  - `AGENTS.md` 文档优先级
- **原始复现/验证步骤**：对照阅读 `Requirements.md` 的 MVP 边界与 `phase4_implementation_roadmap.md` 的 v1.0 要求。

#### Referee 裁定
- **最终裁定**：Accepted
- **决定性证据**：上位文档 `Requirements.md` 与下位文档 `phase4_implementation_roadmap.md` 对同一 MVP 边界给出直接相反要求。
- **简要解释**：这是最明确的硬冲突项；若不先修复，compile-time YAML 会把错误版本边界写死。

### DOC-002：Phase 1 大量使用“伪精确设计”：把未验证的平台规格、性能结论、渲染路径写成硬事实

#### Bug Finder 原始条目
- **影响与得分**：严重（+10）—— 这类内容一旦进入硬约束 YAML，会把需要真机、平台 API、HDR 实测后才能确认的事项，错误编译成“不可违背的既定事实”。
- **原始判断**：文档错误；仅属实现待完成，不应写入编译约束；文档缺失关键约束。
- **原始证据**：
  - `workspace-agents/design_docs/phase1_capacity_estimation.md:5-13,21-25,31-34,50-52`
  - `workspace-agents/design_docs/phase1_physical_architecture_diagram.md:67-117`
  - 对照 `workspace-agents/Requirements.md:24,27` 与 `workspace-agents/quality_gates.md:29-33,50-61`
- **原始复现/验证步骤**：搜索 `无风险`、`低风险`、`自动透传`、`无需手写` 等表述，并与上位文档的“待验证”要求对照。

#### Referee 裁定
- **最终裁定**：Reduced
- **决定性证据**：`phase1` 的确把大量假设和估算写得过硬，但其文档类型本身包含估算/蓝图属性。
- **简要解释**：核心问题成立——这些内容不能直接硬化；但更准确的定性是“探索性内容缺少边界标记”，而非所有内容都已被证伪。

### DOC-003：Phase 文档内部接口契约互相矛盾：同一条帧输出链路在不同文档里分别被写成 MTLTexture、CVPixelBuffer、甚至统一 PersistenceStore

#### Bug Finder 原始条目
- **影响与得分**：严重（+10）—— 若据此生成编译约束，会得到互相冲突的接口定义。
- **原始判断**：文档错误；文档缺失关键约束；帧输出介质、`FileProviding` 调用方向、Persistence 抽象形态在统一前不能直接固化。
- **原始证据**：
  - `workspace-agents/design_docs/phase2_bounded_contexts_and_context_map.md:71-75,137-142`
  - `workspace-agents/design_docs/phase3_interface_contracts.md:47-59,201-213,240-289,296-307`
  - `XrPlayer/PlaybackCore/Domain/Ports/FrameOutput.swift:1-5`
- **原始复现/验证步骤**：对照 phase2/phase3 的接口说明与真实 ports，尝试统一为单一 schema。

#### Referee 裁定
- **最终裁定**：Accepted
- **决定性证据**：帧输出类型与 `FileProviding` 调用方存在直接文本冲突，不是抽象层级差异所能解释。
- **简要解释**：这已经足以阻断硬约束编译；即便忽略 `PersistenceStore` 争议，问题仍成立。

### DOC-004：Phase 2 术语表、战术模型、接口文档与真实代码四套命名体系并存，通用语言已经失效

#### Bug Finder 原始条目
- **影响与得分**：严重（+10）—— 术语失真会让约束、审查规则和自动化 lint 错误命中。
- **原始判断**：文档错误；当前代码偏离文档；相关未统一术语不能直接写进硬约束 YAML。
- **原始证据**：
  - `workspace-agents/design_docs/phase2_ubiquitous_language.md:9-23,61-63`
  - `workspace-agents/design_docs/phase2_tactical_domain_model.md:28-30,63-66`
  - `workspace-agents/design_docs/phase3_interface_contracts.md:181-196`
  - `XrPlayer/FileBrowsing/Domain/ValueObjects/ConnectionInfo.swift:4-29`
  - `XrPlayer/PlaybackCore/Domain/ValueObjects/HDRType.swift:4-10`
- **原始复现/验证步骤**：在仓库搜索 `StorageConnection|PlaybackCommand|GesturePhase|NetworkStatus|Reconnection|VirtualEnvironmentInfo` 并与真实类型对照。

#### Referee 裁定
- **最终裁定**：Reduced
- **决定性证据**：术语确实漂移，但“通用语言已经失效”偏重。
- **简要解释**：更准确的结论是：术语尚未收敛到可硬化的统一词汇表，因此不能直接生成 hard YAML。

### DOC-005：Phase 3 “整洁架构代码结构”把大量并不存在的目录/文件写成现状，和仓库结构严重脱节

#### Bug Finder 原始条目
- **影响与得分**：严重（+10）—— 若 YAML 按这份结构生成，当前代码库会被大面积误判为违规。
- **原始判断**：文档错误；当前代码偏离文档（或文档已严重陈旧）；Phase 3 的目录树、文件清单、调用绑定表不应直接写进硬约束 YAML。
- **原始证据**：
  - `workspace-agents/design_docs/phase3_clean_architecture_structure.md:33-159`
  - 当前仓库文件列表 `find XrPlayer -maxdepth 4 -type f`
- **原始复现/验证步骤**：对照文档目录树与当前仓库文件树，逐项核验若干典型文件是否存在。

#### Referee 裁定
- **最终裁定**：Reduced
- **决定性证据**：文档目录树与当前仓库显著不一致，但也可能是目标态组织方案。
- **简要解释**：成立的是“不能被当作当前现状的 compile-time rule”；更合适的修复是补充目标态/现状标记，而非简单视为纯伪造现状。

### DOC-006：当前主线代码并没有按 Phase 2/3 描述实现“PlayerUI 持有播放模式决策 + 协议化组装”，文档与实现已发生结构性偏离

#### Bug Finder 原始条目
- **影响与得分**：严重（+10）—— 如果先把文档落成硬约束，再看代码，会误以为这一关键架构已经落地。
- **原始判断**：当前代码偏离文档；文档缺失关键约束。
- **原始证据**：
  - `workspace-agents/product_philosophy.md:80-85`
  - `workspace-agents/design_docs/phase2_bounded_contexts_and_context_map.md:56-83`
  - `workspace-agents/design_docs/phase3_interface_contracts.md:154-170`
  - `XrPlayer/XrPlayerApp.swift:42-100`
  - `XrPlayer/FileBrowsing/ViewModels/FileBrowsingViewModel.swift:104-143`
  - `XrPlayer/WindowVideoViewModel.swift:25-55,177-186`
  - `XrPlayer/App/AppCoordinator.swift:13-58`
- **原始复现/验证步骤**：对照阅读文档中的目标架构与当前入口、ViewModel、Coordinator 的实际接线情况。

#### Referee 裁定
- **最终裁定**：Reduced
- **决定性证据**：主线代码尚未达到文档目标架构，但仓库中已存在 `AppCoordinator` 等迁移骨架。
- **简要解释**：这是“实现未完全追上设计”，不是“设计因此无效”；但也足以说明不能把该目标态直接硬化成当前规则。

### DOC-007：Phase 4 把“已完成/已通过”写成事实，但与 known_issues 和当前仓库验证状态冲突，属于高风险陈旧文档

#### Bug Finder 原始条目
- **影响与得分**：中高（+5）—— 若把这些“已完成”描述喂给硬约束或自动审计流程，会错误地把开放问题当成已收口。
- **原始判断**：文档错误；文档层级/优先级错误；仅属实现待完成，不应写入编译约束。
- **原始证据**：
  - `workspace-agents/design_docs/phase4_implementation_roadmap.md:5-11`
  - `workspace-agents/known_issues.md:1-3`
  - 当前工作区 `swift test` 失败，且输出包含旧路径 `/Users/xiongzhipeng/Applications/XrPlayer/...`
- **原始复现/验证步骤**：对照 `phase4` 时间戳、`known_issues` 更新时间与当前 `swift test` 输出。

#### Referee 裁定
- **最终裁定**：Reduced
- **决定性证据**：这些状态文字不适合作为 hard YAML 输入；但不能仅凭较晚日期的 open issues 与当前构建污染，反证较早阶段记录必假。
- **简要解释**：问题成立在“状态性文字不可硬化”，不成立在“该历史记录必然错误”。
