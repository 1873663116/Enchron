# XrPlayer 已知问题

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
