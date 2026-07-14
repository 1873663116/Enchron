# macOS L2 runtime control run

环境：macOS Playback Lab；单一常驻 App；source summary `HDR10.MP4`。控制由 `PlaybackDebugCLI` command inbox 发出，所有列为 `completed` 的命令都收到 completion acknowledgement。

| Case | Media Session evidence | Result |
|---|---|---|
| pause → seek 7.5 | `F1706EAB-F6FC-4B74-B13F-FF1FE77D9084` | 同一会话；Stream Epoch `1 → 2`；target timeline `7.5`；rate `0`；flush completion count `1`；target-or-later sample 被 renderer accepted；operation `completed`。 |
| consecutive seek 25 → 30 | `D98E5C80-3CC9-4D66-BE23-60BB7A95DEC3` | 同一会话；先发请求以稳定结果 `Seek to 25.0 seconds was superseded by a newer request.` 终止并记录 `operation.seek.superseded`；后发请求 `completed`；最终 Snapshot target `30`、Stream Epoch `4`、current time `30.00565`，证明 latest-request-wins。 |
| rate 0.5 → cold switch | 新会话 `EDDBA222-A07F-4CEC-88CF-D25611E973F8` | route `appleCompressed → ffmpegCompressed`；新会话 `initialRate=0.5`；节点 8/9 重新绑定；switch operation `completed`。 |
| play → pause | `EDDBA222-A07F-4CEC-88CF-D25611E973F8` | 两个独立 Runtime Operation 均 `completed`；renderer state 分别同步为 rate `1` 与 `0`。 |
| close | `EDDBA222-A07F-4CEC-88CF-D25611E973F8` | provider delivery 停止；RealityKit / Presentation Binding 失效；removal-flush completion 后 close operation `completed`；Snapshot lifecycle `idle`；JSONL 到 sequence 30，无 cleanup 尾事件丢失。 |
| close → reopen | `63F9F632-4B65-46B9-82CA-C33D2BB3F2E3 → E34C0E31-18F0-4167-8AA4-ECEC4E937F4F` | 同一 App 进程创建不同 Media Session ID；新会话重新完成 nodes 1–9；renderer rendering，`displayedPixelBuffer=true`，sample 与 time 持续增长。 |

`displayedPixelBuffer()` 在 close removal-flush completion 后仍可能返回 renderer 暴露的最后一个可复制 buffer；它不代表 entity 仍处于 active presentation。close 完成由 flush callback、binding/presentation 失效、slot 释放和 lifecycle `idle` 联合证明。

## Typed Snapshot 增强后的再验

当前源码重新启动单一 macOS Playback Lab 后，command inbox 依次接受 `snapshot`、`rate 0.75`、`pause`、`seek 8.5`、`close` 与 `reopen`。六个命令均收到 `completed` acknowledgement。

旧会话 `1D1CF15A-98BD-4B60-94EA-38BF40D9DAC0` 在 seek 后为 Stream Epoch `2`；close 后 Snapshot lifecycle 为 `idle`，last operation 为 completed close，flush count 为 `2`，RealityKit 与 Presentation Binding 均为空。reopen 创建新会话 `2FDA038E-7B1F-4B25-A7FD-91C560CC357F`；刷新 Snapshot 时 sample / accepted renderer input 均为 `3076`，current time 为 `49.500081542`，displayed pixel buffer、RealityKit binding 与 Presentation Binding 均为 `true`。Snapshot 同时把 macOS hardware display facts 标为 `notAvailable`，没有冒充 Vision Pro HDR 证据。

取证结束后再次完成 close，并终止 PlaybackLab。最终没有 PlaybackLab 或 PlaybackDebugCLI 进程；Apple Vision Pro Simulator 保持 `Shutdown`。
