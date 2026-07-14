# PlaybackCore 架构

## 系统主线

```text
Source Admission
→ Media Session
→ Video Sample Provider ─┐
→ Audio Track Provider ──┤
                         ▼
             Renderer Input Coordination
                         ▼
                  Renderer Graph
                         ▼
              Consumer App Adapter
```

两条视频路线的差异在 VideoSampleProvider 内结束。下游只理解可追溯的 compressed Video Sample Stream，不理解 AVAssetReader、AVFormatContext 或其他 Provider 私有对象。

## 模块地图

| Module | Interface | Ownership |
|---|---|---|
| Source Admission | open、source facts、admission result | 调用方提供来源与访问事实；核心决定 Current Media Slot 是否接受。 |
| Media Session | identity、route、lifecycle、operation records | PlaybackCore 独占。 |
| Video Sample Provider | prepare、events、seek、cancel | Apple 与 FFmpeg adapter 各自读取来源；输出统一 Video Sample Stream。 |
| Audio Track Provider | enumerate、select、decode、seek、cancel | FFmpeg 音频实现；两条视频路线共用。 |
| Renderer Input Coordination | video / PCM input、timeline、backpressure、flush、end、error | PlaybackCore 独占。 |
| Renderer Graph | video renderer、audio renderer、shared synchronizer | PlaybackCore 创建并维护；调用方只消费 active video renderer。 |
| Diagnostics | records、Debug Event Stream、DebugSnapshotV1 | PlaybackCore 发布核心事实；调用方事实必须保留 provenance。 |
| App Adapter | renderer consumer、source authorization、UI 与 presentation | 外部调用方拥有，不属于本仓库。 |

## 关键 seam

VideoSampleProvider 是当前真实 seam：Apple Compressed 与 FFmpeg Compressed 都交付 route-owned event、Stream Epoch、Format Revision 和 compressed CMSampleBuffer。

Renderer Input Coordination 是深层模块。它统一两条路线的 enqueue、timeline、backpressure、flush、end 与 error，并让共享 Linear PCM audio lane 与视频使用同一个 synchronizer。

App Adapter seam 位于 active video renderer 之后。核心不 import SwiftUI 或 RealityKit，不建立 entity，也不推测窗口、空间或产品呈现状态。调用方可把 binding facts 作为带 provenance 的诊断事实写回，但这些事实不改变核心播放状态机。

## 节点

```text
1 Source Acquisition
→ 2 Media Session and Route Binding
→ 3 Provider Open Snapshot
→ 4 Video Track Model
→ 5 Route Media Event Stream
→ 6 Video Sample Stream
→ 7 Renderer Input Coordination
→ 8 Renderer Consumer Binding
```

每个启动的节点产生自己的 record，结果只有 succeeded、failed 或 terminatedByCleanup。失败不交给下游补救；cold route switch 创建新的 Media Session。
