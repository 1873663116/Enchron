# PlaybackCore 术语

**PlaybackCore**：读取媒体容器、解封装音视频并组装保留原始编码的 `CMSampleBuffer`，供 Apple AVFoundation 的 sample-buffer renderer 消费。它不实现音视频解码、自定义画面处理或并行产品播放路线。

**Media Source**：一次 open 的输入，包含 locator、provenance、privacy-safe summary 与访问要求。

**Media Session**：一次 accepted open 到 close 或 failed 的身份范围。来源、sample、操作与 renderer graph 都属于同一个 Media Session。

**Current Media Slot**：核心允许占用的唯一 Media Session 位置，用于 open admission 与 stale rejection。

**Provider Open Snapshot**：Provider 打开来源后形成的不可变容器、时长、轨道、codec 与 metadata 事实。

**Track Model**：根据 Provider Open Snapshot 建立的稳定 video、audio 与 subtitle track 身份、来源映射和格式事实。

**Media Sample Provider**：读取容器、建立 Track Model，并把选定轨道转换为 compressed `CMSampleBuffer` 与 timed metadata event 的模块接口。

**Media Event**：sample、format changed、flush、end 或 error。事件必须携带 Media Session、track、Stream Epoch 与 Format Revision 归属。

**Stream Epoch**：区分 seek、reset、reopen 或 cleanup 前后事件世代的单调身份。

**Format Revision**：区分同一轨道格式变化或显式 format override 的身份；它不等于 Stream Epoch。

**Video Sample Stream**：可追溯的 compressed video sample 与 control marker 流。

**Compressed Audio Sample Stream**：选中音轨产生的、保留原始编码与时间信息的 audio `CMSampleBuffer` 流。

**Renderer Input Coordination**：把 compressed audio / video sample 交给 Apple renderer 所需的最小协调边界，通过 AVFoundation Receiver 管理 async backpressure、timeline、enqueue、flush、end 和 error。

**Renderer Graph**：一个 Media Session 使用的 `AVSampleBufferVideoRenderer`、可选 `AVSampleBufferAudioRenderer` 和共享 `AVSampleBufferRenderSynchronizer`。解码与渲染语义属于 Apple AVFoundation。

**Renderer Consumer Binding**：外部调用方把 active video renderer 交给唯一 consumer 后回填的可追溯事实。核心不拥有 consumer、entity 或 scene。

**Detected Projection**：Provider 从来源观察到的投影格式事实。

**Effective Projection**：经过调用方显式 override 后实际交给 renderer 的投影格式。override 只重建 format description，不修改 payload、timing 或 HDR signaling。

**Stereo Layout**：mono、sideBySide 或 overUnder 的显式 format override，与投影和播放时间线正交。

**Debug Event Stream**：Media Session、sample、renderer 和控制操作在状态边界发布的结构化事件流。

**Debug Snapshot**：从当前稳定 records 派生的版本化状态投影，不替代 records 或验收证据。

**App Adapter**：核心外部的调用方模块，拥有来源长期授权、renderer consumer、产品 UI 与 presentation。
