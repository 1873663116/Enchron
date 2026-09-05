# 播放呈现层的平台约束

本文记录 `Modules/Playback` 里**无法从代码本身读出**的事实：RealityKit 与 SwiftUI 在 visionOS 上的实际行为、由缺陷换来的次序约束、以及若干领域模型为何要这样切分。能由代码或断言表达的部分不写在这里。引擎侧（解码、渲染器、时间线）的约束在 `docs/PLAYBACK_ENGINE_CONSTRAINTS.md`。

## RealityKit 的实测行为

- **Entity 进入场景后是异步激活的**。先建立所有权，再插入 entity，**只有在 entity 拿到最终拓扑之后**才安装渲染器组件。次序颠倒时 RealityKit 偶尔会接受一个尚未进入场景的 `VideoPlayerComponent` 而不提交它的渲染目标。
- **共享的播放 Entity 只能从一条非活动链移入正在执行更新的那个 RealityView**。`Entity.isActive` 覆盖它的整条祖先链，因此这个判断不需要任何生命周期回调。
- **跨 RealityView 根的交接必须换新 Entity**。RealityKit 在 Window 与 Immersive 根之间移动之后，不能可靠地重新激活同一个 Entity 与 renderer graph。同一 ownership class 内部的转移则保持身份。
- **visionOS 27**：在 RealityView 场景之间移动 entity，可能留下旧的 current mode 而 requested mode 不变。激活后要在一个有界区间内重发请求，RealityKit 才会在新场景里开始转换。
- **`ContentTypeDidChange` 不标识它的来源 Entity**，RealityKit 也不承诺重新订阅后重放它。因此整个会话只保留一份订阅，用捕获的 media scope 充当 Apple 没有提供的实体身份。
- **组件写入只证明 RealityKit 接受了组件值**。给目标一个有界的提交区间，但**不要**对后续的 `VideoPlayerComponent` 变化去抖：Panorama 的模式协商会在同一个渲染目标仍在使用时持续改动组件。
- **重挂稳定播放 entity 不增删它的 `VideoPlayerComponent`**，所以不保证会有组件事件；attach 处的 active-entity 守卫仍然拦住"非活动目标场景被报告为就绪"。
- **刚安装的组件在分类期间合法地报告没有 current mode**，而重写同样的 desired 值会重启这次分类。所以先等是对的，但只能等到分类合理完成为止：设备实测一个正在落定的表面约一秒内报出模式，而在转换中途被交给替换技术会话的表面可能**永远**报 nil，没有上界就再也没有东西去重试它。
- **`realityScripting` 自带一个 targeted `SpatialTapGesture`** 用来给脚本喂 `TapGestureEvent`，它就在这个视图内部。普通的 `.gesture` 会把每一次捏合都输给它，必须同时识别（simultaneously）才能让脚本系统与播放都看到这次点击。
- **RealityKit 不激活留在编译后环境资源里的空 transform marker**。保留它的稳定身份与 authored 世界变换，但让它成为一个活的 RealityView 根，它的播放子节点才能激活。

## UIKit 与 SwiftUI 的场景生命周期

- **渲染器在 UIKit 断开来源 Window Scene 之前不能跨 RealityView 根**。运行时释放所有权是必要条件而不是充分条件——它不证明 RealityKit 已经移除了异步的视频目标。**SwiftUI 根的 `onDisappear` 在 visionOS 上不是 Window 生命周期契约。**
- **新建的 WindowGroup 实例已经是 `openWindow` 的前台结果**。再去激活它的 UIKit scene 会引发系统呈现崩溃，并且不提供任何额外契约。
- **visionOS 丢弃针对 App 唯一窗口的 `dismissWindow`**，不报错也不留日志。浏览与播放之间的窗口交接因此必须先开新窗口、观察到它开启、再关旧窗口；同一个同步回合里连发两个动作，关闭请求在新场景存在之前抵达，静默失效。2026-08-31 模拟器实测：等待 `windowObservation` 报出新窗口 `.open` 之后再关，同一次关闭即生效。
- **`WindowGroup(id:for:)` 的 `defaultValue` 每次求值都产出一个新值时，无参数的 `openWindow(id:)` 每次都开一个新窗口**。产品语义上唯一的窗口必须声明为 `Window`，由场景类型保证唯一，而不是靠每个调用点记得携带同一个值。
- **被 await 的 scene action 就是平台完成边界**。SwiftUI 不保证 ImmersiveSpace 内容的 `onDisappear` 在该 action 返回之前运行。
- **一个已消失的场景不能再接受平台请求**，但它持有的活动 lease 仍然有效，好让同一次执行经由新注册的场景根继续下去；`currentCapability` 则立刻停止暴露那个退休场景的动作。

## 窗口与视频的几何

- 控制条固定 728pt 悬在窗口下方，所以更窄的窗口会戴上一条比它自己还宽的控制条，窗口宽度下限由此而来。
- **每一档是目标面积，不是外接盒**。外接盒自带一个形状，会饿死不共享该形状的一方——mono 源上的并排覆盖曾经因此要求一个几千点高的窗口。高度永远由宽度与视频自身比例导出，两个夹取都缩放整个矩形，窗口因此不可能与画面不一致而挣得一条空玻璃带。
- **每个能拥有窗口的表面各自声明自己的范围，没有一个在离场时恢复系统默认**。这样"一个表面消失"与"下一个出现"的先后就不会留下一个无约束的窗口。浏览页没有视频可匹配，形状固定 16:9，不欠播放任何东西；Portal 同样锁在视频的比例档上，它自己没有尺寸规则。
- **窗口视频网格与 Window 的 SwiftUI 平面共面**，并带 `ModelSortGroup.planarUIInline`——按 z 排序而不是按视图树。画在视频之上的 chrome 因此需要一个向前的位移，否则网格赢下平局、chrome 永不出现。这个位移**只能**用在布局边界落在窗口圆角以内的视图上：整窗偏移会离开 2D 裁切，显示为围着玻璃的一圈尖角矩形。
- **Portal 需要它的 Window scene 里有空间厚度**。取值是 SwiftUI 场景单位，对齐 Apple 沉浸媒体 PlayerWindow 契约；零厚度的宿主会让组件停在 loading。

## 沉浸空间的几何与输入

- **Immersive Space 的原点在佩戴者脚下的地板上**。authored anchor 携带佩戴者的名义眼高，距离与仰角把屏幕放在以该点为中心的球面上。
- **交互壳必须够到远高于站立眼高、也远出常规房间尺度移动的范围**，佩戴者能占据的每一个眼位都留在壳内、留在每一块面板之外。面板做得薄，是为了让一条离开壳的注视射线恰好穿过其中一块。180° 投影只拥有前半球，360° 拥有所有方向。
- **透明 SwiftUI attachment 接不到真实注视**。2026-08-10 的佩戴者实测里 8/8 次捏合都未命中它。Apple 自己的沉浸媒体示例用一个带 input target 的**不可见碰撞实体**接收召唤捏合，本产品照此办理。
- `PlaybackSurfaceRealityKitAdapter.dock` 用 `look(at:from:relativeTo:)`，其默认前向是本地 -Z，而 `VideoPlayerComponent` 画面的可见面是本地 +Z；因此 look 的目标取佩戴者的反方向，让 +Z 朝向佩戴者。让 -Z 朝向佩戴者会呈现画面的背面，左右镜像。子碰撞体沿 +Z 正偏移才在视频前面，与窗口呈现一致。

## 呈现转换的所有权与次序

- **运行时 attachment 属于转换的目标呈现**（没有转换在跑时就是已落定的那个）。离场的窗口表面在主窗口关闭完成前仍然挂载，如果在替换技术会话上把它重新 attach，就等于从沉浸表面手里把 attachment 抢回来，此后 settlement 永远无法提交，整次打开在 executor 的期限上回滚。
- **一次呈现内部的技术会话替换没有 Scene 消失来退休上一个视频实体**。把它留在原位，它的 `VideoPlayerComponent` 会继续把最后一帧喂在新表面之上；而每个被保留的渲染器都让自己的解码管线在 `mediaplaybackd` 里活着，直到该守护进程触到内存上限。
- **consumer record 必须携带 renderer epoch**。记录以 Entity 身份为键，而 entity store 在渲染器被替换时铸造新 Entity，因此来自更早 epoch 的记录指向一个再也无法呈现的 Entity。不带 epoch 时这种记录会拒绝新渲染器上的每一次认领、表面永远重试，因为唯一能清除它的代码被那个已经被替换掉的身份守卫着。
- **目标表面通常自己启动 cutover**，就在它证明自己的像素带着当前身份的那一刻，这是退出快的原因。executor 侧的 settlement 是同一份证明晚一个来回到达，用于表面**没得到机会**的情况（没有后续 RealityView 更新，或转换在它脚下变了）。
- **播放中的 transfer 必须先推进替换渲染器**，RealityKit 才能在每一种呈现里确认第一个显示像素；暂停的 transfer 没有成功后意图，保持暂停。
- **等待必须有界**。调用方在整个等待期间持有平台执行 lease，无界等待会让这个 lease 被永远占住，此后每一个空间请求都被拒绝直到应用重启。界限取得宽，是因为高分辨率全景启动本来就慢——但没落定的表面不是"启动慢"，是卡住了。

## 主窗口列在哪些呈现里还在

- **window 与 portal 保留主窗口列，panorama 与 docked 不保留**。窗口 chrome 只能在这两种呈现里由表面点击召唤，格式菜单也只在召唤之后才接受点击；沉浸式呈现下窗口已经空了，表面点击没有落点。见 `Scripts/verification/playback_transition_stress.py`。
- **投影只在主窗口列里改变**。panorama 与 docked 两个格子因此只有"退出空间呈现"这一条边，从 panorama 直接 apply-flat 是一条同时改投影与改呈现的对角边。见 `Scripts/verification/playback_transition_stress.py`。
- **被来源信令标注为全景的内容，在有人请求 panorama 之前落在 portal**。只把 window 当作合法落点，集合里每一个空间片都会走到超时。见 `Scripts/verification/playback_open_sweep.py`。

## 注视输入下的控件判定

注视解析到的落点比光标粗得多，窗口播放控件的几处判定都由此而来：

- **一个目标里面不要再放小目标**。播放信息井是可点开的整块，井里再放一个小控件，它会把本该属于井的点击接走。井内元素因此只作指示，不接受输入。
- **注视点亮之处必须就是捏合起始之处**。scrubber 的可见抬升贴着画出来的拇指，而外层那圈胶囊才是接住手的范围；它与 `isThumbHit` 用同一几何，因此凡是注视落下并点亮控件的地方，捏合都能开始一次拖动。
- **水平轨道只测水平距离**。手势挂在整条 strip 上，起始位置在纵向已经通过了 strip 的 interaction 形状；决定"佩戴者是不是要拖这个 scrubber"的轴只有沿轨道那一个。
- **松手之后 scrubber 锁存在目标值上**。`onSeek` 之后运行时的位置是异步追上来的，锁存期内拇指钉住目标，否则会出现"跳回旧位、再闪到目标"。运行时位置进入容差（或兜底超时）即释放。
- **展开时间轴的唯一事实是 `contentWidth = duration × pps`**。拖拽极限、标尺与胶片末端全部以它为准；单独截短整体会与拖拽极限脱节，而且在最小缩放下一格约合数十秒，白白丢掉可拖范围。

## 窗口控件的自动隐藏

- **窗口播放控件在一段空闲之后自动隐藏，这段窗口的长度由启动参数给定**。一个要证明"打开菜单会钉住控件"的场景必须把它压到自己的探测点之前，否则读到的 controls=shown 由启动参数保证，与产品无关。见 `Scripts/verification/regression_preparation_adapter.py`。

## 探针文件的写入纪律

诊断探针写在应用容器里，被证据链读取，因此它的体积是一条真实约束：

- **每种日志一个去重槽**。把每帧的表面事实与 attach 探针共用一个槽，会让两者都无法重复自己的上一个值，于是 attach 探针每帧触发并把探针文件冲爆。
- **时钟与计数器字段不能进去重签名**。它们每帧前进，会让每一条 settlement 行都独一无二，文件增长快到中途卡死容器拷贝。
- **沉浸打开的竞态只表现为两次 attach 的先后**，因此它必须进探针文件，并按技术会话去重。

## 领域模型为何这样切分

- **Media Format 的来源信令事实不可变**。用户的解释永远不改写它们，Automatic 解析回这份事实而不是制造一个平面回退。会话面向的解释是单一值，呈现策略消费它时不再回读可变的运行时字段。
- **playback-mode family 与 Media Format 分开持久化**：投影与立体解释留在 `formatPreference` 里。
- **Dolby Vision 的 profile 与 layers 分开存**。`HDRType` 只能命名一种动态范围，而 Profile 7 的来源同时有两个答案：它是 Dolby Vision，而到达佩戴者的是它的基础层。layers 决定回退，profile 号只是一个名字。profile 后面那个数字是**交叉兼容性**，即基础层还能被读作哪种动态范围（8.4 是 HLG 兼容，8.1 是 HDR10 兼容）——它不是 level，level 数的是分辨率与码率档次。
- **`UnmetCapability` 不是 `PlaybackError`**。后者的每个 case 都是终止性的，于是"画面播了但第二视图缺失"或"音频编码被拒因而静音播放"无处可记，只能以一张没有解释的画面到达佩戴者。决定这类事实显示在哪里的唯一区别是**究竟播了没有**，所以那是这里唯一的轴；再细的分级（比如严重度阶梯）是各表面用不上的分类。这里的每个字段都已由 PlaybackCore 发布，本文件不探测设备：看不见的能力是事实集的缺口，不是可以用启发式推断的东西。
- **播放边界只接受已注册的字节来源**。远程调用方必须先注册字节来源，任意网络 URL 因此无法绕过 MediaSource 直接进入播放。
- **来源发现不越过持久化的用户覆盖**。文件自报的事实记录下来，但优先级低于交给这次技术会话的用户覆盖。
- **只有产品状态能证明一个 RealityView 永不落定**，经过的墙钟时间不能。首帧慢的表面在活动媒体请求的整个生命周期内保持 attach 资格。
- **`PlaybackUserVisibleIssue` 只接受有界的产品事实**，`Error` 与任意诊断字符串进不了这个类型，因此呈现代码永远不需要判断一段文本是否可以示人。
- **ProRes 解码器可用性经 `VTDecompressionSessionCreate` 实测**，不从渲染器的错误文本推断。见 `Tests/EnchronApp/VideoDecoderAvailabilityTests.swift`（真机 lane 专有，模拟器上按构造失败）。
- **旧构建暴露过一个 Apple 元数据专属的投影选项**，它已不再是用户可选的投影；解码时把它读成普通矩形视频，是为了保住那些偏好里带着旧值的媒体仍能播放。同类的还有把早期那个单一占位环境迁移到第一个稳定的 Scenic 身份（断言见 `EnvironmentSceneMappingTests`），Skybox 有意永不作默认。
- **`ViewingStatePolicy.mutation` 删除时长低于 `minimumContentDurationSeconds = 15 * 60` 的条目的观看状态**（`Modules/Playback/Domain/ViewingState.swift:50-56`）。只有长过这个常数的条目，退出后才留下可续播的状态。
- **local-aggregate 固件集里最长的一条是 120.064 s，整集都落在该常数之下**。`generated-viewing-storage-h264-16m01s-v1` 以 898 KB 承载 961.0 s，是集合里唯一在常数之上的条目，automatic-play-next-resume-policy 依赖它。见 `Scripts/verification/regression_preparation_adapter.py`。

## 面板的三步展开

面板的每一次切换分三步：内容退场（外壳仍持有正在离开的尺寸）、空外壳行进到进入的尺寸、内容入场。中途到达的请求**重定向**这次变化而不是排在它后面，改主意的佩戴者因此不必坐等一次已被放弃的变化走完；外壳已空时再次进入 `contentLeaving` 在屏幕上不花任何代价，却让实现免于逐阶段的特例。每一步的完成启动下一步，所以次序跟随动画本身，而不是在这里重复一份可能与 `DesignTokens` 漂移的时长。按钮的选中态跟随"正在落定的块"而不是当前 layout，否则它会在内容退场那段时间里闪回。次序断言见 `Tests/PlaybackPresentationTests/PlaybackPanelExpansionTests.swift`。
