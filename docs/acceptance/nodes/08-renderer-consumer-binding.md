# 节点 8：Renderer Consumer Binding

节点 8 记录外部 App Adapter 是否把节点 7 的 active video renderer 交给唯一 active consumer。PlaybackCore 不创建 consumer、RealityKit entity、RealityView 或 SwiftUI scene。

输入是 Media Session、route、renderer graph identity，以及调用方提供的 consumer / binding identity 与 provenance。输出是 binding record。

稳定规则：

- renderer、consumer 与 binding 必须属于同一 Media Session。
- 任意稳定时刻同一个 renderer 只有一个 active consumer。
- renderer graph replacement 或 cold route switch 后，旧 binding 不再 active。
- cleanup 后旧 consumer 不代表当前播放。
- binding facts 不能替代 renderer enqueue、可见画面或产品呈现证据。

唯一完成条件：调用方报告的 active consumer identity 与当前 renderer identity 一致，且记录属于当前 Media Session。实际 UI 和显示效果由调用方验证。
