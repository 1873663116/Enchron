# PlaybackCore 验证系统

这里规定节点推进、测试层级、vertical slice、证据格式和完成声明。系统结构见 `../../ARCHITECTURE.md`，设计要求见 `../core-spec.md`，当前通过状态只从 `evidence.md` 读取。

## 证明原则

验证针对事实边界，不针对 UI 文案或“看起来像能播”。每个用例只有一个预期结果。以下事实分别记录，不能互相替代：

- open 被接受。
- Media Session 与显式 route 被绑定。
- Provider 打开来源并建立 track facts。
- Provider 产生 sample。
- sample 被标准化并被 renderer 接受。
- renderer 进入 rendering state。
- RealityKit component 引用 active renderer。
- entity 进入 active `RealityView`。
- displayed pixel buffer 出现。
- 时间线持续推进。
- 人类在 Vision Pro 看到正确画面与 HDR 观感。

一条 route 的证据不能推断另一条 route。旧 xr-fork evidence 不能推断当前 PlaybackCore。

## Open Operation

accepted `open(source:route:)` 创建 Open Operation，并把节点 2–9 的 records、失败和 cleanup 归到同一个 Media Session。state 只有：

| State | Meaning |
|---|---|
| `running` | open 已接受，节点链正在推进。 |
| `completed` | 节点 9 已形成可解释 Presentation Binding。 |
| `failed` | 某个必要节点失败，失败边界已记录。 |
| `terminatedByCleanup` | close 或 cold switch 终止了 open 链。 |

Open Operation completed 不等于连续播放通过。displayed frame、持续推进和 ended 是独立验证用例。

## 节点推进

每个实际启动的节点产出稳定 record。节点 operation 结果只有：

| Result | Meaning | Advance |
|---|---|---|
| `succeeded` | 当前节点产出成功 record。 | 是 |
| `failed` | 当前节点产出失败 record。 | 否 |
| `terminatedByCleanup` | cleanup 终止 operation。 | 否 |

失败不交给下一个节点补救。当前不自动 fallback；用户显式切 route 会创建新的 Media Session 和新的节点链。

## Vertical slices

### Slice 1：公开 open 到可解释 presentation

每条 route 都必须独立完成：

1. source facts 进入公开 `open(source:route:)`。
2. accepted open 创建 Media Session、Route Binding 和 Open Operation。
3. Provider Open Snapshot 记录真实 Provider 的 open facts。
4. Video Track Model 建立 primary video track。
5. 真实 Provider 产生至少一个 Route Media Event。
6. 节点 6 交付至少一个当前 route 的 Video Sample Record。
7. 节点 7 在 first enqueue 前建立 timeline，并记录 accepted renderer input。
8. 节点 8 建立 active RealityKit Renderer Binding。
9. 节点 9 记录 entity 已进入 App Adapter 的 active `RealityView`。
10. Debug Snapshot 可以沿同一 Media Session 解释整条归属链。

### Slice 2：可见持续播放

每条 route 独立证明：

1. renderer 没有不可恢复 error。
2. displayed pixel buffer 出现。
3. sample count 和 synchronizer time 在同一会话中继续推进。
4. backpressure 没有形成无界 queue 或被误报为 failure。

macOS Playback Lab 可以关闭这条 L2 slice。它不提供 Vision Pro HDR 结论。

### Slice 3：close、stale rejection 与 reopen

1. `close()` 停止 Provider delivery 和 renderer request。
2. renderer flush、RealityKit binding 和 Presentation Binding 不再代表旧会话。
3. Current Media Slot 释放。
4. 旧 session / epoch callback 不能更新当前 facts。
5. 同一 App 进程可以再次 open 并恢复 displayed frame。

### Slice 4：运行控制

分别验证 play、pause、setRate、single seek、consecutive seek、setVolume、setMuted、audio track selection、close、reopen 和 cold route switch。每个 request 单独形成 admission、对应 operation 或 renderer-state effects，以及完成 / 失败记录；不能用一组最终 UI 状态替代每个控制自己的结果。

### Slice 5：音频与音视频同步

分别证明音轨枚举、默认选择、显式轨道切换、PCM sample 持续提交、音量、静音，以及 seek / pause / rate 后音视频仍由同一个 synchronizer 时间线驱动。Snapshot 必须证明 audio renderer、video renderer 和 synchronizer 属于同一个 Media Session 与 graph；轨道切换准备失败的用例必须证明旧轨、rate / paused state 和 PCM delivery 被恢复。renderer enqueue 只能证明链路工作；实际可听声音与主观 lip-sync 另记 L2/L3 人工证据。

### Slice 6：visionOS 呈现状态

visionOS presentation 以四种派生产品形态、Playback Window lifecycle 与独立 Scene Lifecycle 验证：

| Case | Fixture | Single boundary |
|---|---|---|
| Playback Window lifecycle | 无媒体 | 同一个标准 WindowGroup 可 open / close，且不创建 Media Session。 |
| Scene lifecycle | 无媒体 | 唯一使用 progressive `ImmersionStyle` 的 Playback `ImmersiveSpace` 可 open / close，显示 RCP `customScene`，且不创建或迁移播放器。 |
| Flat Window | runtime planar mesh + `VideoMaterial` | entity attached to Playback Window 的唯一 `RealityView`，不以 immersive mode 作为成功条件，且不改写来源 projection metadata。 |
| Portal Window | APMP 全景 | 同一个 window / RealityView / entity 使用 acknowledged `.portal`。 |
| Docked | runtime planar mesh + `VideoMaterial` | Scene 已 open，entity 挂到由 RCP `world/screen` transform 建立的纯 docking anchor，Scene Content 为 `customScene`。 |
| Panorama | APMP 全景 + `VideoPlayerComponent` | 同一个 ImmersiveSpace 切为 `blackPanorama`，全部 RCP 场景隐藏，不使用 docking anchor，实际 `.progressive` 被 acknowledgement。 |

产品形态切换必须保持同一个 Media Session 和 renderer identity，并分别记录实际 `RealityView`、Scene Content、RenderingStatus 与 transition result。Portal / Panorama 另外必须记录 `ImmersiveViewingModeDidChange` acknowledgement 和 desired / actual viewing mode；Flat / Docked 将该 mode 记录为不参与成功判定。普通平面 fixture 证明 Flat / Docked；APMP fixture 证明 Portal / Panorama。两者不能互相替代。

自动回归只执行 UI 暴露的合法命令序列，不验证后端非法边拒绝矩阵。Portal / Panorama 中没有 Dock，Scene closed 时没有 Dock，Docked 中没有 Portal；这些纯 UI 能力约束由少量 UI smoke 或人工检查关闭。

## 验收层级

| Layer | Environment | Proves | Cannot prove |
|---|---|---|---|
| L1 core facts | macOS host tests、contract fixtures、fake adapters | records、route mapping、sample facts、state machine、epoch / revision、renderer intent、Debug Snapshot schema。 | 真实 Apple renderer、RealityKit 承载、可见画面。 |
| L2 integration | 优先 macOS Playback Lab；必要时 visionOS Simulator | 真实 Provider、Apple renderer、synchronizer、RealityKit binding、`RealityView`、displayed frame、public controls；Simulator 补 platform-only scene / API。 | Vision Pro HDR / EDR、设备显示、thermal、佩戴体感。 |
| L3 device facts | Vision Pro | 真实设备显示、HDR / EDR 观感、设备性能和不可等价系统行为。 | 不重新替代 L1/L2 的结构化基础证据。 |

L2 不是“所有东西必须搬到 visionOS Simulator”。如果 macOS 使用同一核心、同一 Provider、同一 renderer API 和同一 RealityKit binding，并且待证明事实与 visionOS 等价，macOS 证据就是主要 L2。只有 scene lifecycle、API availability 或平台行为确实不同的部分才进入 Simulator。

## 节点与主要验证层

| Node | Primary layer | Required proof |
|---|---|---|
| 1 Source Acquisition | L1 / L2 | source facts schema；系统入口或明确 test provenance。 |
| 2 Media Session and Route Binding | L1 | slot、session identity、route immutability、rejection、cleanup。 |
| 3 Provider Open Snapshot | L1 / L2 | 每个真实 Provider 的 open facts 与 failure boundary。 |
| 4 Video Track Model | L1 | stable track ID、source mapping、selection 与 missing states。 |
| 5 Route Media Event Stream | L1 / L2 | event ownership、epoch、format revision、end / error；真实 Provider delivery。 |
| 6 Video Sample Stream | L1 / L2 | route-specific sample contract、timing、format、ownership。 |
| 7 Renderer Input Coordination | L1 / L2 | fake sink semantics；真实 audio/video renderer graph、共享 timeline、各自 enqueue / backpressure、flush 与 end。 |
| 8 RealityKit Renderer Binding | L1 / L2 | identity / uniqueness model；真实 `VideoPlayerComponent(videoRenderer:)`。 |
| 9 RealityView Presentation | L2 | 真实 `RealityView` attach、presentation provenance、displayed frame surrogate。 |

## Route matrix

每条 route 至少具有以下独立用例：

| Case | Single expected result |
|---|---|
| L1 Provider Open | 该 route 产出成功 Provider Open Snapshot。 |
| L1 First Sample | 该 route 产出 compressed Video Sample Record；sample 的 image buffer 为 nil、data buffer 非 nil，format description 为 compressed media subtype。 |
| L2 First Enqueue | timeline 在 first enqueue 前建立，renderer 接受至少一个 sample。 |
| L2 Displayed Frame | renderer 产生 displayed pixel buffer。 |
| L2 Sustained Progress | 同一 Media Session 的 time 与 sample facts持续推进。 |
| L2 Close / Reopen | 同一进程 close 后重新 open，新的 Media Session 再次产生 displayed frame。 |

Dolby Vision Profile 5、8.1、8.4 是 Apple Compressed 的额外独立格式与 L3 观感用例，不替代一般 route matrix。

## Runtime control cases

- play request 的唯一预期结果：synchronizer rate action 被记录为目标播放速率。
- pause request 的唯一预期结果：synchronizer rate action 被记录为零。
- setRate request 的唯一预期结果：合法目标 rate 被 synchronizer 接受并进入当前状态。
- single seek 的唯一预期结果：active Provider seek、Stream Epoch 更新、renderer flush 和 synchronizer target time 按合同完成。
- consecutive seek 的唯一预期结果：最后一个 accepted request 的 target 成为 completed target。
- seek-conflict 的唯一预期结果：seek 尚未完成时，非 seek timeline control 被明确拒绝为 `operationInProgress(.seek)`；新的 seek 可以 supersede 旧 seek。
- cold route switch 的唯一预期结果：旧 Media Session cleanup 后，新 route 建立新的 Media Session。
- close 的唯一预期结果：Current Media Slot 释放且旧 callback 被拒绝为 stale。
- reopen 的唯一预期结果：旧 cleanup barrier 完成后，新 Media Session 以同一 source、route 与 access requirement 建立，不复用旧 renderer graph。
- audio track selection 的唯一预期结果：所选 raw stream index 在当前时间重建音频输入并恢复 enqueue。
- failed audio track selection 的唯一预期结果：旧轨、旧 rate / paused state 与 PCM delivery 被恢复。
- volume 的唯一预期结果：active audio renderer 的 volume 更新并进入 snapshot。
- mute 的唯一预期结果：active audio renderer 的 mute state 更新并进入 snapshot。
- Playback Window open / close 的唯一预期结果：同一个标准 WindowGroup 到达目标 lifecycle；无媒体前置条件下不得创建 Media Session。
- Scene open / close 的唯一预期结果：唯一 Playback `ImmersiveSpace` 到达目标 Scene Lifecycle；已有 window video binding 时不得迁移 entity、替换 renderer 或改变 Media Session。
- video placement 的唯一预期结果：renderer-backed entity 从旧 presentation binding 转移到已打开的目标 scene binding。

## Debug Snapshot 验证

L1 先验证 node / operation records，再验证 `DebugSnapshotV1` 与 records 一致。Snapshot 不能替代 records。

Snapshot 必须：

- 有 schema version。
- 保留 typed missing state。
- 不记录完整私有 path。
- 可编码为稳定 JSON。
- 保留 Media Session、route、node、epoch、format revision 和 evidence correlation。
- 将 App Adapter presentation facts 与 core facts 标注不同 provenance。
- 在 Simulator 中把 hardware-only facts 写为 `unknown` 或 `notAvailable`，不得伪造设备结论。

## Debug Event Stream 验证

事件 sequence number 单调递增；同一节点状态边界最多发布一次等价事件；sample heartbeat 使用聚合信息，不逐帧刷日志。测试必须证明 subscriber 在 App 运行期间可以接入、读取当前 snapshot、继续接收事件，并在不重启 App 的情况下执行下一次 open / control / close 诊断。

## 代码驱动的真机集成回归合同

本节只定义回归合同，不授权自动发起真机测试。任何签名、安装或启动前，操作者都必须针对本次运行明确确认 Vision Pro 已佩戴、解锁且可测试；设备已连接、历史上曾确认或脚本已准备好都不能替代这次确认。

集成回归不拥有任何 probe 专属呈现编排。它只在输入端替代独立 Control Window 中的 SwiftUI 控件，连续调用公开 `PresentationCommand` 并读取公开状态；只有 Window Bar、Playback Window / Immersive Space 无控件遮挡和错误禁用等纯 UI 行为另做人工或 UI smoke。集成回归只有同时满足以下事实才通过：

1. 每次运行生成唯一 run ID，先删除或绕开旧结果；回收文件的 run ID 必须与本次运行一致。
2. manifest 固定为 49 个独立 case：无媒体的 Window / Scene open / close lifecycle 4 个；2 routes × 4 shapes 共 8 个；Window 播放中 Scene open / close 不迁移 2 个；固定同一个 Apple Compressed APMP Media Session 的 4 shapes × 2 Stereo round-trips 共 8 个，该组不得为每个 case reopen；Panorama 从 Scene closed / `customScene` open 进入，并分别通过 showWindow 与 closeMedia 恢复进入前状态，共 4 个；产品公开的合法 edge 3 个；2 routes × 9 个原子播放控制共 18 个；cold route switch 1 个；final cleanup 1 个。九个原子控制是 pause、play、rate、seek、audio track selection、volume、mute toggle、reopen 和 close，不再与 Shape、Stereo、Scene 或 Projection 做全排列。
3. 精确 `caseID` schema 是：`lifecycle.{playbackWindowOpenWithoutMedia|playbackWindowCloseWithoutMedia|customSceneOpenWithoutMedia|customSceneCloseWithoutMedia}`、`shape.{appleCompressed|ffmpegCompressed}.{flatWindow|portalWindow|docked|panorama}`、`scene.windowPlayback.{openDoesNotMigrate|closeDoesNotMigrate}`、`stereo.{flatWindow|portalWindow|docked|panorama}.mono-{sideBySide|overUnder}-roundTrip`、`scene.{panoramaFromClosed.restoresClosed|panoramaFromOpen.restoresCustomScene|closeMediaFromPanorama.restoresClosed|closeMediaFromPanorama.restoresCustomScene}`、`edge.{dockedToFlatWindow|dockedToPanorama|panoramaToFlatWindow}`、`control.{appleCompressed|ffmpegCompressed}.{pause|play|rate|seek|audioTrack|volume|muteToggle|reopen|close}`、`route.appleCompressed-to-ffmpegCompressed.coldSwitch` 和 `cleanup.final`。这组展开后的 49 个 ID 是合同，不允许测试自行改名或增删。
4. 结果出现缺失、重复或未声明 `caseID` 时，`completed` 必须为 false；只有实际 `caseID` 集合与预期集合完全相等且每个 case 都到达终态，才能写 `completed = true`。每个 case 记录实际 route / source（不能用 UI selected route 代替）、Candidate / Presented Product Shape、Detected / Effective Projection、Media Session / renderer / video Entity identity、目标 acknowledgement surface、保留引用的 baseline pixel 与 fresh pixel identity、timeline、Scene 与 rollback state / error。失败 case 也必须保留已经采集的 baseline、中间状态与 target；缺少任何 required evidence key 必须 fail closed。结果根级还必须记录 Git HEAD、dirty worktree、状态摘要与全部受版本控制／未忽略文件内容的 SHA-256、Xcode / visionOS SDK、设备标识与设备 OS，以及 Flat fixture、Panorama fixture 和 bundled Reality asset 的 SHA-256；只记录文件名与摘要，不记录本机完整路径。缺少这组 provenance 时整次运行 fail closed；没有 provenance 的旧结果不能证明当前构建。
5. presentation case 必须证明 target-first 顺序，并等待目标 scene attached、Entity parent / binding、必要的目标 view mode acknowledgement、transition settled、`RenderingStatus == ready`、当前 renderer 无 error、转换后的 displayed-pixel observation，以及 sample count / synchronizer time 相对 baseline 推进。Flat / Portal 目标还要求 Playback Window open；Docked / Panorama 目标要求 Playback Window closed。固定 sleep 只能作为 polling interval 或 timeout，不能构成成功事实。
6. Flat / Docked 必须记录 runtime planar mesh、`VideoMaterial` 与来源 projection metadata 未改写；Docked 还要记录保留 RCP `world/screen` authored transform 的纯 runtime docking anchor binding 和 `customScene`。Panorama 必须使用 APMP fixture，记录 `blackPanorama`、全部 RCP 场景不可见、未绑定 docking anchor，以及 requested / actual `.progressive`；Portal 必须在同一个 Playback Window `RealityView` 观察 actual `.portal`。第一版没有独立 `.full` case；`.progressive` 只记录平台的 Immersion Style / viewing mode，不作为第五种 Shape。
7. Stereo 不与其他维度做全排列。Flat Window、Portal Window、Docked、Panorama 各自独立验证一次 `mono ↔ sideBySide` 与 `mono ↔ overUnder`；每个 case 的唯一预期结果是目标 Stereo 生效且产品形态、Projection、Scene 与 Placement 不变。
   固定 APMP fixture 接近结束时，可在下一个 case baseline 之前对同一 Media Session seek-to-zero；该维护动作不得更换 Media Session、renderer 或 route，也不属于 Stereo case 的结果。
8. cold route switch 必须证明旧 Media Session cleanup、新 Media Session / renderer / video Entity identity、同一 source，以及新路线重新产生 sample 与 displayed pixel；不能沿用旧路线的 pixel 或 sample count，也不能重置 Shape、Projection、Placement、Stereo、Scene Intent、paused / rate、volume、mute 或 audio selection。
9. final cleanup 必须等待 Provider cancel、audio/video renderer flush、binding invalidation 与 Current Media Slot release。结果文件只有在全部 case 完成时写 `completed = true`，全部 case 通过时写 `passed = true`；启动脚本必须解析两者并在任一不满足时非零退出，同时终止 App。

这些条件证明自动可观察的结构、scene 与播放事实，不证明 Vision Pro 的 HDR / EDR、可听输出、主观同步或空间观感。

## Evidence 规则

每条完成声明必须引用 Evidence ID。记录至少包含：

- Evidence ID、case / node / route。
- L1 / L2 / L3。
- commit 或 working-tree identity。
- fixture ID / hash 或 privacy-safe source summary。
- environment 与执行入口。
- artifact 路径或结构化输出。
- status：`verified`、`failed`、`blocked`、`stale`、`invalidated`。
- result summary、limits 和 superseded evidence。

源码、fixture、依赖或目标事实变化后，旧 evidence 必须重新判断是否 stale。人工观察可以构成 L3 evidence，但必须写明操作协议、比较对象和失败标准。

## 当前已知证据边界

当前代码已经产生双路线 macOS 播放、Apple Compressed Vision Pro Dolby Vision 与 FFmpeg Compressed 格式证据；具体有效范围见 `evidence.md`。xr-fork 的历史 L1 / L2 evidence 只作为实现可行性输入，不参与当前状态推导。
