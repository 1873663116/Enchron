# 节点 9：RealityView presentation

## 作用与边界

节点 9 由 macOS Playback Lab 把节点 8 的 renderer-backed video entity 放入 active `RealityView`。它记录 App 承载和可见帧推进，不负责 renderer 输入或 `VideoPlayerComponent` binding。

完成条件是当前 Media Session 的 video entity 已加入 active `RealityView`。首个 tracer bullet 只要求 attach 可解释；当前 video-only slice 完成还要求 Agent 能观察同一个短小 fixture 的视频帧连续推进。

## 输入与输出

输入包含 `mediaSessionID`、节点 8 binding identity、renderer-backed video entity、active `RealityView` identity 和 App lifecycle state。

输出是 Presentation Binding Record。记录说明 binding identity、video entity identity、`RealityView` identity、entity attached state、sample provenance、最近 attach 或 detach，以及是否已经观察到当前 slice 要求的帧推进。

## 稳定规则

presentation、video entity 和 RealityKit binding 必须属于同一个 Media Session。video entity 只能在 active `RealityView` 中声明最终绑定。App 尚未 ready、旧 Media Session、重复最终绑定或 cleanup 后更新不能写成成功。

entity attach 和可见帧推进是两个不同事实。结构化 attach 不能代替真实播放观察；可见画面也不能代替节点 6 的 sample 结构证明。

## 验收方向

L2 使用 macOS Playback Lab 分别验证 Apple Sample Reference Path 与 PlaybackCore Target Path。每个用例只有一个预期结果：真实 video entity 被加入 active `RealityView`；随后独立用例证明 fixture 的视频帧连续推进。

具体观察方式、结构化快照和 App lifecycle 用例由实现阶段使用 `$tdd` 决定。
