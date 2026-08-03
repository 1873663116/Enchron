# 节点 06：Renderer-ready Sample Stream

## 边界

节点 06 把 Media Event 标准化为 renderer-ready audio/video `CMSampleBuffer` 或 control marker。产品 FFmpeg provider 负责从 packet、codec parameters 和 extradata 组装 compressed video sample；音频由同一个 provider 组装为 AVFoundation 可直接接收的 compressed sample，或解码为交错线性 PCM sample。所有 sample 进入相同 downstream seam。

## Video sample

每个 video sample 至少保留 Media Session、Track ID、source event、Stream Epoch、Format Revision、PTS、DTS、duration、sample count、keyframe/dependency attachments、format identity、compressed media subtype、dimensions、codec configuration、color/HDR/Dolby Vision、projection/stereo signaling 与 payload ownership。

## Audio sample

每个 audio sample 至少保留 Media Session、Track ID、Stream Epoch、PTS、duration、来源 codec、实际 format description、channel layout、sample rate 与 ownership，并交给当前 audio renderer lane。compressed audio 还必须保留 codec configuration；decoded audio 必须是交错线性 PCM，且仍由相同 FFmpeg provider、Media Session、timeline 与 renderer lane 拥有。

## 完成条件

唯一完成条件：当前 active lane 已产出至少一个满足合同的 sample 或明确 control marker。renderer 是否接受属于节点 07。

## 验收

PlaybackCore 合同测试验证 FFmpeg sample 生产与共同 downstream 行为。视频首样本必须有 compressed data buffer 而没有 image buffer；compressed audio 验证 codec configuration，FLAC 验证实际输出为交错线性 PCM 且完整 drain 全部 frame。覆盖 B-frame、missing format、codec configuration、range、HDR、format change、stale epoch 与 cleanup。
