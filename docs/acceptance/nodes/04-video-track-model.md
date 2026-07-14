# 节点 4：Video Track Model

## 作用与边界

节点 4 把 Provider Open Snapshot 的 raw video track facts 转换成 PlaybackCore-owned track identity、格式事实和选择结果。它不读取 Provider 私有对象，不创建 `CMSampleBuffer`。

## 输入

- Media Session ID、route。
- Provider Open Snapshot identity。
- raw video track mappings 与 normalized codec / timing / metadata facts。

## 输出

Video Track Model Record 至少包含：

- Media Session ID、route、source snapshot identity。
- tracks list。
- primary Video Track ID。
- selection result。

每条 track 至少包含 opaque `videoTrackID`、raw source mapping、codec facts、dimensions、nominal frame rate、timebase、format summary、selected 和 not-selected reason。

Video Track ID 不等于 AVAsset track identity、FFmpeg stream index、codec ID 或 UI index。raw identity 只保存在 source mapping。

## 第一版选择规则

当前 video track lane 选择一个 primary video track。没有可用视频轨时节点失败。未选择的其他视频轨仍保留在 record 中并说明 `notChosen`、`unsupported`、`missingRequiredFacts` 或其他稳定原因。共享 Audio Track Provider 是平行 lane，不改变本节点的视频选择结果。

## 完成条件

唯一完成条件：当前 Media Session 已建立一个可供节点 5 路由的 selected primary Video Track ID。sample 是否可生产属于节点 5 / 6。

## 验收方向

L1 使用 Apple Compressed 与 FFmpeg Compressed 两个 Provider 的真实 snapshot fixtures 和受控 edge cases，验证 stable identity、source mapping、selection、missing state 与节点边界。
