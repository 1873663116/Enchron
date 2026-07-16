# 节点 06：Compressed Sample Stream

## 边界

节点 06 把 Media Event 标准化为 compressed audio/video `CMSampleBuffer` 或 control marker。产品 FFmpeg provider 负责从 packet、codec parameters 和 extradata 组装 sample；Apple reference provider 验证 storage-format sample 后进入相同 downstream seam。

## Video sample

每个 video sample 至少保留 Media Session、Track ID、source event、Stream Epoch、Format Revision、PTS、DTS、duration、sample count、keyframe/dependency attachments、format identity、compressed media subtype、dimensions、codec configuration、color/HDR/Dolby Vision、projection/stereo signaling 与 payload ownership。

## Audio sample

每个 audio sample 至少保留 Media Session、Track ID、Stream Epoch、PTS、duration、codec configuration、channel layout、sample rate 与 ownership，并交给当前 audio renderer lane。产品目标不建立 PlaybackCore-owned 长期 PCM 播放路线。

## 完成条件

唯一完成条件：当前 active lane 已产出至少一个满足合同的 sample 或明确 control marker。renderer 是否接受属于节点 07。

## 验收

L1 验证 FFmpeg 与 Apple reference 的独立 sample 生产，再比较共同 downstream 行为。视频首样本必须有 compressed data buffer 而没有 image buffer；覆盖 B-frame、missing format、codec configuration、range、HDR、format change、stale epoch 与 cleanup。
