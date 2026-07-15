# PlaybackCore 架构

## 系统主线

```text
Source Admission -> Media Session -> Demux Provider
                                         |-- compressed video sample stream
                                         |-- compressed audio sample stream
                                         `-- track and timed metadata facts
                                                    |
                                                    v
                                      Renderer Input Coordination
                                                    |
                                                    v
                                            Renderer Graph
                                                    |
                                                    v
                                         Enchron App Adapter
```

## 所有权

- `Source Admission` 接受调用方提供的来源与访问事实，并管理唯一 Current Media Slot。
- `Media Session` 拥有一次 open 到 close/failed 的身份、生命周期、操作和 stale rejection。
- `Demux Provider` 读取容器、建立轨道模型，并输出保留原始编码与时间信息的 audio/video `CMSampleBuffer`。它不解码媒体。
- `Renderer Input Coordination` 通过 AVFoundation Receiver 管理 audio/video async backpressure、timeline、enqueue、flush、end 和 error。
- `Renderer Graph` 组合 `AVSampleBufferVideoRenderer`、可选 `AVSampleBufferAudioRenderer` 与一个 `AVSampleBufferRenderSynchronizer`。解码与渲染语义属于 AVFoundation。
- `Diagnostics` 发布带 Media Session、Stream Epoch 和 Format Revision 的 records、事件与快照。
- `Enchron App Adapter` 拥有来源长期授权、renderer consumer、RealityKit、SwiftUI 和产品呈现，不属于本仓库。

## 接口约束

公开 open 接口接受 Media Source，不接受播放路线。产品只有一条 sample-buffer 路径；Apple sample reader 可以作为验证参考，但不是第二个产品 adapter。

Provider 私有对象、裸 FFmpeg pointer 和可变 container state 不越过 provider interface。compressed sample 必须在离开 provider 后继续满足 payload ownership、timing、format description、sync attachment 与 metadata 合同。

调用方只能通过公开控制接口操作当前 Media Session，并消费 active video renderer。它不能直接修改 renderer queue、timeline 或内部状态机。

## 当前迁移状态

源码已迁移到 macOS 27 / visionOS 27 的 AVFoundation Receiver 与 `AVAssetReaderOutput.Provider` 接口，但仍含 Apple/FFmpeg 双路线、FFmpeg audio decode、Linear PCM 和 cold route switch 等旧实现。它们是迁移输入，不是目标架构；迁移完成前，测试通过只能证明现有实现没有回归，不能证明本文件定义的单一路径已经完成。
