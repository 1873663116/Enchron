# ADR-0008：恢复 Enchron macOS App 作为核心可播放门槛

- 状态：accepted
- 日期：2026-07-16
- 取代：ADR-0006 中“核心完成只需 library 测试与低层 probe”的部分

## 背景

ADR-0006 正确地把产品 App、SwiftUI scene 和空间呈现移出 PlaybackCore，但同时把真实 AVFoundation renderer、RealityKit consumer、可见画面与可听音频也移出了核心完成条件。随后 Receiver async enqueue 等核心路径变化只经过编译、单元测试和低层 probe，未先通过历史 Verify App 所提供的 macOS L2。产品接入后出现无法持续播放和颜色异常时，已经没有位于核心与 visionOS 产品之间的稳定失败边界。

## 决策

PlaybackCore 继续是纯 library，不新增 App target，也不拥有 RealityKit entity。Enchron 同时提供 macOS App；其中的 Core scenario 直接验证 PlaybackCore，并由 PlaybackCore 的验证规格定义 fixture、节点、控制矩阵和通过门槛。

只有 L1 Core Contract 与 L2 Enchron macOS 都通过，当前 revision 才能声明 PlaybackCore 可播放。之后才运行 Enchron App Adapter scenario、visionOS Simulator 和 L3 Vision Pro 验收。

Apple compressed reference 与 FFmpeg compressed 产品路线使用同一媒体和同一节点 7–9 实现分别运行；前者不作为 fallback，也不替代后者的结果。

## 考虑过的替代方案

- 继续只使用 unit test 与低层 probe：无法证明真实 Receiver、共享 synchronizer、RealityKit consumer、音频和 displayed pixel 的组合行为。
- 把验证 App 放回 PlaybackCore：会重新让核心仓库拥有客户端 target 与平台 UI 生命周期。
- 直接以 Enchron visionOS App 首验：产品状态、来源、scene 与设备差异会遮蔽核心的第一失败节点。

## 后果

- Enchron 必须维护 macOS App 及其核心验证模式，但不能建立第二播放状态机。
- 核心 API、Receiver、sample assembly、timeline 或 renderer graph 变化必须先通过 L2，才能进入产品连接与 Simulator。
- 可播放声明需要真实视频、音频、控制、颜色/HDR 信令与稳定性证据；build 和测试数量不再足够。
- HDR 最终观感、空间模式和设备性能仍只由 L3 证明。
