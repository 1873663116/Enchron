# XrPlayer 已知问题归档（已修复）

归档日期：2026-03-06

## 收口结论

- ✅ 播放控件首次打开音轨/字幕二级菜单卡顿：已通过内嵌面板宿主替代首次 popover 懒初始化路径完成收口。
- ✅ KI-001 / KI-002：已完成 bundled CJK 字体、`sub-fonts-dir`、`sub-font-provider=none` 等字幕链路修正；模拟器 smoke 已验证字幕可见。
- ✅ KI-003：已完成 warmup、视频层握手、首帧 loading 时机修正和本地文件 readahead 调优。
- ✅ KI-004：播放控件与二级面板交互已切换到新的控件内面板方案，旧的 popover 动画路径不再作为当前实现。
- ✅ KI-005：二级时间轴已切换为固定中心指针 + 时间带拖动 + 松手提交精确 seek 的交互实现。

以下保留归档前的原始问题记录，供后续追溯。

---

# XrPlayer 已知问题（Known Issues）

更新时间：2026-03-06

---
## 通过播放控件点开其二级菜单的卡顿

### 现象
-在还未开启字幕时，只是第一次点开音轨和字幕的二级菜单就会让视频陷入停滞级卡顿，伴随滋滋声，这似乎代表完全卡死，不过只持续约1s，
-只在第一次打开时出现此问题，接下来就不会出现这个问题。
-这是完全不应该的，理论上其只是打开UI，不应该造成任何卡顿。

原因目前未知。

### 调查结论（2026-03-06）

当前代码证据表明，**高概率不是点击按钮时才去 mpv 同步拉取音轨/字幕数据**。轨道列表会在 `MPV_EVENT_FILE_LOADED` 后立即缓存到 `internalAudioTracks` / `internalSubtitleTracks`，播放菜单读取的是这份缓存，而不是首次打开菜单时再同步查询 mpv。

更高概率的原因是：**第一次展示 `.popover` 时，visionOS 需要懒初始化整套 popover 宿主、`NavigationStack`、`List` 和对应布局树**，而这个面板又挂在播放中的底部 ornament 上，首次构建成本被压到了正在播放的视频 UI 上，因此出现约 1 秒停滞级卡顿。第二次再打开时不再复现，也符合“首次懒初始化”的特征。

### 代码证据

- `PlayerControlsView.swift` 中点按按钮只是 `showTracksMenu.toggle()`，没有在按钮点击路径上调用 mpv 查询逻辑。
- `PlaybackMenuView.swift` 只是消费 `videoViewModel.availableAudioTracks` 与 `videoViewModel.availableSubtitleTracks`。
- `MPVPlayerAdapter.swift` 在 `MPV_EVENT_FILE_LOADED` 和后续 `track-list` 属性变更时就会调用 `refreshTrackCache()`，提前把轨道信息缓存好。

### 解决方向

1. 预热菜单宿主：在播放器控件首次显示时提前创建一次菜单壳体，避免首次点击时做整套 UI 懒初始化。
2. 去掉首次打开时的重容器：如果不需要栈式导航，尽量避免在一个简单轨道面板里使用 `NavigationStack + List` 组合。
3. 若保留当前结构，首次点按时也要先秒开壳体，再异步补内容，不能阻塞播放。
4. 用 Instruments 验证首次点击时的主线程热点，确认是否确实集中在 SwiftUI layout / popover host 初始化。

### 置信度

中等偏高。当前代码足以排除“首次点击才查轨道数据”，但还需要一次 Instruments 采样把“popover 首次懒初始化”从高概率推断提升为已证明。

## KI-001：真机播放 ASS 字幕时极度卡顿（未修复）

### 现象
- 开启 ASS 字幕后，视频播放帧率严重下降，画面明显卡顿。
- CJK（中文/日文/韩文）字幕下尤为严重，几乎无法正常观看。
- 关闭字幕后立即恢复正常帧率，说明卡顿根源可能来自字幕。
- 即使添加了添加了 `sub-ass-override=strip` 降级，仍然会出现此问题。说明问题不在性能上。

### 根因分析

#### 根因 A：libass 无法找到 PingFang SC 字体 ← **最主要根因**

这是理解所有字幕问题的关键。

`MPVConfiguration.swift` 第 110 行配置了：
```swift
("sub-font", "PingFang SC"),  // 注释称 "built into visionOS"
```
该注释描述是**错误的**。`sub-font` 选项是告诉 libass **想用哪个字体名称**，但 libass 必须自己**找到**该字体文件才能使用。

libass 在 Linux 上通过 **fontconfig** 发现系统字体。**fontconfig 在 visionOS/iOS 上根本不存在**。libass 在 visionOS 上可以找到字体的方式只有两种：
1. `sub-fonts-dir` 指向一个目录，该目录下有对应的 `.ttf`/`.otf` 文件
2. ASS 文件自身内嵌了字体数据（`[Fonts]` 段）

由于两者均未满足，libass 找不到 PingFang SC 的字体文件。它的 fallback 链条为：
1. 尝试在 `sub-fonts-dir`（未设置）里找 -> 失败
2. 尝试 fontconfig（不存在）-> 失败
3. 使用内置紧急字体（FreeSerif / FreeSans）-> **不含 CJK 字形** -> 字符显示为方框（□）

**字体找不到，导致 libass 每个字形都要走完整的 fallback 扫描流程，每帧渲染开销暴增。**

#### 根因 B：libass 的字幕栅格化完全在 CPU 上完成

libass 的架构：
1. 解析 ASS 脚本事件（CPU）
2. 用 FreeType + HarfBuzz 进行字体 shaping（CPU）
3. 渲染描边、阴影、光晕等特效（CPU 软件光栅化）
4. 输出 RGBA 位图

**GPU 不参与步骤 1-4**。这是 libass 的根本架构限制，不是配置问题。

对于有多层特效的复杂 ASS（中文字幕通常有描边+阴影），单帧渲染时间可达 10-50 ms，直接导致帧时间超标。

#### 根因 C：`blend-subtitles=no` 增加了额外的 CPU->GPU 拷贝开销

当前代码（`MPVConfiguration.swift:119`）：
```swift
("blend-subtitles", "no")
```
OSD 模式下的渲染流程：
1. libass 在 CPU 渲染字幕为 RGBA 位图
2. 通过单独的 OSD 通道上传到 GPU
3. GPU 在视频帧之上做 alpha 合成

代码注释声称 `blend-subtitles=yes` 会"在 GPU pipeline 线程上强制同步 ASS 渲染，导致音频缓冲饿死"。**这个诊断是错误的**，音频饿死是**根因 A**（字体找不到导致单帧耗时暴增）的结果，不是 `blend-subtitles=yes` 本身的问题。修复字体问题后，`blend-subtitles=yes` 应当能正常工作，且合成效率更高。

#### 补充说明：为什么“走 GPU”不能直接解决 ASS 卡顿

这里需要澄清一个容易混淆的点：**libass 本身不是 GPU 字幕渲染器**。它的主工作仍然是 CPU 侧完成的：
1. 字体发现
2. 文本 shaping
3. 描边/阴影/模糊等 ASS 特效栅格化
4. 产出字幕位图

`blend-subtitles=yes` 的价值主要在于**最后一步合成尽量走 GPU**，减少 OSD overlay 模式下的额外上传与合成开销；它并不会把 libass 前面的 CPU 排版与栅格化工作魔法般迁移到 GPU。

因此，这个问题的正确优化顺序是：
1. 先修字体发现链路，否则 CPU 侧成本会异常放大；
2. 再评估是否改回 `blend-subtitles=yes`，把字幕最终合成尽量留在视频 GPU 管线里；
3. 不要期待仅靠 GPU blend 就解决全部 ASS 性能问题，CPU 仍然是主战场。

### 解决方向

1. 在 App Bundle 内捆绑至少一套可用的 CJK 字体，并显式配置 `sub-fonts-dir`。
2. 修复字体链路后，重新 A/B 对比 `blend-subtitles=yes` 与 `blend-subtitles=no` 的真实表现。
3. 若 ASS 仍旧过重，再考虑按字幕复杂度做降级策略，而不是把问题归咎于“GPU 没开”。

---

## KI-002：真机 CJK 字幕字符显示为方框（乱码）（未修复）

### 现象
- 在真机上开启 ASS 字幕（含中文/日文/韩文）后，所有 CJK 字符均显示为 □（方框）。
- 英文字母、ASCII 标点正常显示。

### 根因

当前最强假设仍与 KI-001 根因 A 相同：**libass 在 visionOS 上很可能没有找到可用的 CJK 字体**，于是回退到不含 CJK 字形的后备字体。

但这里的确定性还不该写满。现有证据能证明“结果上没有拿到可用 CJK 字形”，还不能单靠当前代码直接证明是“字体发现链路中的哪一段”失效。更稳妥的说法是：**问题高度疑似出在字体发现 / fallback / 打包字体缺失这一整条链路**，而不是已经精确定位到某一个内部节点。

已在 KI-001 中详细分析，不再重复。

### 修复路径

同 KI-001：捆绑字体 + 设置 `sub-fonts-dir`。

---

## KI-003：打开大型视频文件时黑屏数秒（未修复）

### 现象
- 用户在文件浏览器中选择视频文件后，播放器界面显示纯黑，持续 2-8 秒后视频开始播放。
- **首次播放（冷启动后）尤为严重**；同一会话内切换文件时较短但依然存在。
- 市面上其他播放器可以"秒开"相同或更大的文件。
- **加载指示器（ProgressView）已添加，但黑屏延迟本身没有改善**。

### 调查结论（2026-03-06）

这不是单一 bug，而是**首播冷启动 + native GPU 输出路径存在时序风险 + 启动链路串行 + 本地文件仍使用激进缓存策略 + UI 状态切换过早**叠加出来的黑屏窗口。

#### 根因 A：真机默认走 native GPU 路径，但 warmup 在该路径上是 no-op

`XrPlayerApp.swift` 启动时确实调用了 `player.warmup()`，但 `MPVPlayerAdapter.warmup()` 内部对 `useNativeGPUOutput == true` 直接 `return`。也就是说，**真机首播时并没有真正预热 mpv 上下文**；真正的 `mpv_create -> applyConfiguration -> mpv_initialize -> loadfile` 仍然发生在用户点开文件之后。

#### 根因 B：native GPU 输出依赖视频层先 attach，但当前只做“限时等待”，超时后仍继续启动

`play(url:)` 里第一步会执行 `waitForVideoLayerIfNeeded()`。但这段逻辑并不是“没有 layer 就不许继续”，而是**最多轮询 1.2 秒**；一旦超时，即使 `videoLayer` 仍然是 `nil`，后续也照样继续执行 `ensureMPVReady()` 和 `loadfile`。

而 `ensureMPVReady()` 是否走 native GPU 路径，取决于那一刻 `videoLayer != nil` 是否已经成立：
- 若 layer 已及时 attach，则 mpv 会按 native GPU 路径配置；
- 若 layer 还没 attach，就会退回非 native GPU 的启动分支。

这就是这里说的“时序风险”：**黑屏是否出现、持续多久，不只取决于“有没有 layer”，还取决于“layer attach”和“mpv 初始化/装载文件”谁先发生**。两个本来应该协同的异步步骤，现在只是靠 1.2 秒轮询去碰运气对齐，所以在首播、界面初次创建、设备负载较高时更容易暴露问题。

换成更直白的话说：播放器启动时需要等“屏幕上的承载层”准备好，但代码现在只愿意等 1.2 秒；如果这 1.2 秒内 SwiftUI 还没把 layer 挂上来，播放器也会硬着头皮往下跑。这样就很容易出现“播放器已经开始初始化甚至开始 loadfile 了，但真正用来显示首帧的层还没准备好”的黑屏窗口。

#### 根因 C：播放启动路径落在 `@MainActor` 调用链上，首次打开大文件时串行等待更明显

`WindowVideoViewModel.play(url:)` 是 `@MainActor` 上的方法，它直接 `await player.play(url:)`。而 `player.play(url:)` 内又会做：
1. `waitForVideoLayerIfNeeded()`
2. `ensureMPVReady()`
3. 文件存在性/可读性检查
4. `startAccessingSecurityScopedResource()`
5. `loadfile`

虽然真正的 demux / decode 在 mpv 内部，但**启动链前半段已经足够让主线程体验到明显等待**。

#### 根因 D：当前配置更像“流媒体友好”，不是“本地大文件秒开友好”

当前默认开启：
- `cache=yes`
- `demuxer-max-bytes=16MiB`
- `demuxer-readahead-secs=3`

这对网络流更合理，但对本地大文件的“尽快首帧”目标并不理想，可能增加起播前缓冲与探测成本。

#### 根因 E：UI 以 `FILE_LOADED` 作为“开始播放”的近似时机，而不是“首帧真正显示”

当前 `MPV_EVENT_FILE_LOADED` 触发后就把状态切到 `.playing`。但这并不等于首帧已经显示到屏幕上。原生视频层本身默认是黑底，因此**只要首帧还没真正 present，用户看到的就是纯黑等待**。

### 代码证据

- `XrPlayerApp.swift` 调用了 `player.warmup()`。
- `MPVPlayerAdapter.warmup()` 在 native GPU 路径直接 no-op。
- `MPVPlayerAdapter.waitForVideoLayerIfNeeded()` 最多只等待 1.2s，超时后仍继续 `ensureMPVReady()`。
- `MPVPlayerAdapter.ensureMPVReady()` 仅在 `videoLayer != nil` 时才会按 native GPU 路径配置。
- `WindowVideoViewModel.play(url:)` 在 `@MainActor` 上直接调用 `player.play(url:)`。
- `MPVConfiguration.swift` 默认启用了 `cache=yes`、`demuxer-max-bytes=16MiB`、`demuxer-readahead-secs=3`。
- `MPVPlayerAdapter.swift` 在 `MPV_EVENT_FILE_LOADED` 时切换到 `.playing`。
- `MPVNativeMetalLayerView.swift` 的底色就是黑色。

### 解决方向

1. 让真机 native GPU 路径也能真正 warmup，而不是只对软件渲染路径预热。
2. 把“等待视频层 ready”从限时轮询改成更可靠的握手机制，避免超时后带着 `videoLayer == nil` 继续初始化。
3. 把 `player.play(url:)` 启动链路里的非必要主线程工作尽量挪走，尤其是初始化与准备阶段。
4. 为本地文件单独调优 cache / readahead 策略，目标从“稳态缓存”改成“尽快首帧”。
5. 把 UI 的 loading 结束条件从 `FILE_LOADED` 调整为更接近“首帧已可见”的时机。
6. 补采样日志，拆开统计 `layer ready`、`mpv_initialize`、`loadfile`、首帧显示各阶段耗时。

### 置信度

高。虽然各子阶段的精确耗时比例还需要日志或 profile，但问题确实是多因素叠加，不是单一“黑屏 bug”。


---

## KI-004：播放控件 UI 从右下角动画进出，而非居中

### 现象
- 播放时单击召唤控件栏，控件从右下角浮现出来。
- 控件消失时也向右下角缩回，而不是居中缩回。

### 修复内容

删除了 `PlayerControlsView.swift` 中的 `onAppear` 重置块。该块在 popover 首次弹出时触发 `showTracksMenu = false`，导致 popover 立即关闭。`@State` 变量在声明时已初始化为 `false`，`onAppear` 的重置完全多余。

### 调查结论（2026-03-06）

当前代码树已经无法完整复原“旧版本为什么看起来是从右下角进出”的全部细节，因为文档中提到的旧 `onAppear` 重置块已经不在工作树里。

不过可以确认的是：
- 播放控件当前挂在 `MainView.swift` 的 bottom ornament 上，锚点本身是居中的；
- 但进出场动画仍然使用 `.move(edge: .bottom).combined(with: .opacity)`，因此它的视觉来源是“从下边缘进入/退出”，而不是严格的“原地居中淡入淡出”。

这说明：
1. 文档记录的旧问题大概率已经被部分修掉；
2. 当前剩余的是**空间定向感与动画锚点不一致**的问题，而不一定还是当时那个具体的状态重置 bug。

### 解决方向

1. 控件进出场改为居中锚点的淡入/缩放/深度变化，而不是 `.move(edge: .bottom)`。
2. 二级菜单从按钮上方展开，主控件本体不应被带着一起位移。
3. 若需要追溯历史根因，必须查看更早的未保留提交或外部备份，当前工作树已不足以 100% 复盘。

### 置信度

中等。当前树足以说明“现在为什么还不像原地居中”，但不足以完全证明“旧的右下角来源感”到底是哪一段历史代码单独造成的。

---

## KI-005：二级进度条UX用户不满意，且二级进度条的性能存在问题，目前拉动二级进度条远远不如一级进度条流畅。

### 描述
二级进度条不应该继续沿用传统播放进度条的交互逻辑。它应当更接近剪辑软件的时间带：
- 中间固定一根指针，表示当前时刻；
- 用户左右拖动的不是“指针”或普通 slider thumb，而是**指针下方那条代表整段视频总时长的长圆角矩形时间带**；
- 这条时间带应当以中间指针为中心进行缩放；
- 时间刻度不再放在矩形外部上方，而是**直接绘制在矩形内部**，从而节省空间，并在时间带到达容器视觉上限后仍能通过内部刻度密度变化保持明显反馈。

缩放逻辑也不是传统 slider zoom，而是两阶段表现：
1. 当时间带尚未达到容器上限时，缩放会直接改变这条圆角矩形的可见长度；
2. 当时间带已经触达容器极限长度后，外轮廓不再明显变长，但**内部时间刻度与时间映射仍继续同步变化**，避免界面看起来“卡住不变”。

此外，目前注视点可识别区域过小也是独立问题。现在除了进度条本体外，二级进度条周围的大部分区域都不容易被 Vision Pro 稳定识别，导致拖拽、缩放和选择操作都缺乏足够的 gaze hit area。

而左右上一帧和下一帧的控制按钮，需要居中，并且位于最下方，也就是时间刻度放大缩小拉杆的下方。
/Users/xiongzhipeng/Downloads/二级进度条参考图片.png

### 调查结论（2026-03-06）

这条问题由**交互模型定义错误**、**gaze 命中区域过小**与**拖动期间每帧直接触发精确 seek**三个层面共同造成。

#### 根因 A：当前实现本质上仍是传统 slider，而不是“固定中心指针 + 可拖动时间带”

`DetailedTimelineView.swift` 当前使用的是：
- 一条 fill bar
- 一个 thumb
- 按当前窗口比例计算 fill 宽度

这与期望中的模型不是同一种交互。你要的不是“拖动一个进度点”，而是：
- 中心指针始终固定不动；
- 指针下方的时间带内容左右滑动；
- 时间刻度直接内嵌在时间带内部；
- 时间带缩放以中心指针为锚点，而不是沿用普通进度条的 fill / thumb 语义。

#### 根因 B：可注视与可交互区域太小，不符合 Vision Pro 的 gaze 操作需求

当前二级进度条真正容易被识别和选中的，主要只有细窄的进度条主体。对于 Vision Pro 这类依赖注视点的交互方式，这会直接导致：
- 用户难以稳定选中拖拽区域；
- 缩放与拖动操作容易丢失；
- 看起来“已经修了 UI”，但实际使用时仍然费力、不可靠。

这说明当前问题不只是视觉层级，而是**命中区域设计不足**。需要把时间带整体及其周边留白一并作为可交互区域，而不是只让细线或局部矩形承担命中。

#### 根因 C：拖动中每次 `onChanged` 都直接触发 `seek(to:)`

当前二级进度条的 `DragGesture.onChanged` 会在每一个拖动更新里直接调用 `videoViewModel.seek(to:)`。而 `WindowVideoViewModel.seek(to:)` 又会立即同步调用播放器 seek；播放器内部使用的是 `absolute+exact` seek，并在 seek 后立刻回读 `playback-time`。

这意味着用户拖动得越密，播放器就被迫越频繁地做精确跳转，自然会远远不如一级进度条顺滑。

### 代码证据

- `DetailedTimelineView.swift` 的主体是传统 fill bar + thumb。
- `DetailedTimelineView.swift` 在 `DragGesture.onChanged` 中直接 `videoViewModel.seek(to:)`。
- `WindowVideoViewModel.swift` 的 `seek(to:)` 立即调用播放器 seek。
- `MPVPlayerAdapter.swift` 的 `seek(to:)` 使用 `absolute+exact`，并在之后同步读取 `playback-time`。

### 解决方向

1. 先把交互骨架改成真正的“固定中心指针 + 可拖动时间带 + 内嵌时间刻度 + 底部缩放与帧进按钮”。
2. 时间刻度改为绘制在时间带矩形内部，不再占用矩形外部上方空间。
3. 时间带缩放以中心指针为锚点；达到容器最大长度后，继续通过内部刻度密度和时间映射变化体现缩放，而不是让界面停在视觉上无变化的状态。
4. 显著放大二级进度条整体的 gaze hit area，让用户能稳定注视和操作时间带周边，而不是只命中细窄主体。
5. 拖动时不要每次都直接驱动精确 seek。应当先更新本地拖拽状态，再做节流预览或在松手时提交。
6. 如果需要拖动中预览，预览也应区分“轻量更新”和“最终落点”，避免每个手势采样都走 `absolute+exact`。
7. 帧进/帧退应作为最终微调动作，而不是靠高频精确 seek 模拟。

### 置信度

高。这条问题在当前代码里非常直接，不需要额外猜测。
