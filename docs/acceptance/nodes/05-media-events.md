# 节点 05：Media Event Stream

## 边界

节点 05 让当前 provider 为节点 04 的 active tracks 建立连续 Media Event Stream。它负责事件归属、生命周期、Stream Epoch、Format Revision 和 payload ownership；节点 06 负责组装标准 sample。

事件包括 `sample`、`formatChanged`、`flush`、`end` 和 `error`。每个事件必须携带 event ID、Media Session ID、Track ID、Stream Epoch、Format Revision 与 provider provenance。

## 世代与所有权

Stream Epoch 区分 seek、reset、reopen 与 cleanup 前后的事件；Format Revision 区分同一轨道的格式版本。两者不能合并。节点 06/07 必须拒绝旧 epoch 或旧 revision 输入。

FFmpeg packet bytes 在越过 read callback 前必须复制或完成等价 ownership transfer；Apple reference storage sample 的 CoreMedia ownership必须在 provider 生命周期外仍有效。裸 C pointer、mutable format context 和 AVFoundation 私有 reader 对象不能越过 provider seam。

## 完成条件

唯一完成条件：当前 active track 已交付至少一个可由节点 06 消费的事件，或明确 end/error。持续播放不是本节点结果。

## 验收

L1 验证 ownership、session/track mapping、epoch/revision、format change、B-frame ordering、seek flush、end、error、cancel 与 cleanup 后迟到事件。
