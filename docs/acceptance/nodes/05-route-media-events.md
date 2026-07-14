# 节点 5：Route Media Event Stream

## 作用与边界

节点 5 让 selected Provider 为节点 4 的 primary Video Track 建立连续事件流。它负责事件归属、生命周期、epoch、format revision 和 payload ownership；节点 6 负责把事件标准化为 Video Sample Stream。

## 事件类型

| Event | Meaning |
|---|---|
| `sample` | 当前 route 产生的 Apple storage compressed sample 或 FFmpeg-owned compressed packet/sample。 |
| `formatChanged` | 新的 track format facts 生效，创建新的 Format Revision。 |
| `flush` | 旧 Provider stream / queue state 失效，通常伴随新的 Stream Epoch。 |
| `end` | Provider input 结束；不是 public ended。 |
| `error` | Provider read、demux、compressed sample production 或 ownership failure。 |

每个 event 都携带 event ID、Media Session ID、route、Video Track ID、Stream Epoch、Format Revision 和 provider provenance。

## Stream Epoch 与 Format Revision

Stream Epoch 区分 seek、reset、reopen 和 cleanup 前后的事件世代。Format Revision 区分同一 track 的格式版本。seek 可以只改变 epoch；format change 可以只改变 revision。节点 6 / 7 必须拒绝旧 epoch input。

## Ownership

Apple storage `CMSampleBuffer` 必须在离开 Provider 后仍满足 CoreMedia ownership。FFmpeg packet bytes 必须从 `AVPacket` 生命周期复制到 PlaybackCore-owned storage，或在 sample 创建时完成等价 ownership transfer。

Provider 私有对象、裸 C pointer 和 mutable format context 不进入 event interface。

共享 FFmpeg audio decode / PCM stream 是 Media Session 的平行 lane，不进入这个视频 Route Media Event Stream，也不构成第三条 Playback Route。

## Failure record

Route Media Event Stream Failure Record 记录 Media Session、route、track、failure stage、last event / timing、Provider error 和 recoverability。单个 sample build failure属于节点 6；无法继续产生事件属于节点 5。

## 完成条件

唯一完成条件：当前 route 已为 selected track 建立事件流并交付至少一个可由节点 6消费的 event，或明确 end。持续播放另作验证。

## 验收方向

L1 验证 ownership、route / session / track mapping、epoch / revision、format change、end、error 和 cleanup。L2 证明真实 Provider event 进入同一公开 open vertical slice。
