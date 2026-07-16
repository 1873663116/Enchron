---
status: accepted
date: 2026-07-14
supersedes: ADR 0005 and the broader ownership in ADR 0006
---

# AVFoundation 拥有解码与渲染，PlaybackCore 收束为解封装边界

PlaybackCore 收束为单一产品路径：读取容器、解封装音视频并组装保留原始编码的 `CMSampleBuffer`，再交给 Apple AVFoundation 的 sample-buffer renderer。Apple 负责音视频解码、HDR / Dolby Vision 解释与最终渲染；PlaybackCore 只保留 sample 投递所必需的 session、控制、同步和 renderer input coordination，不再拥有 FFmpeg 音频解码、decoded pixel 路线、双产品路线切换、自定义画面处理或画面参数模型。这一取舍用更窄的自有媒体边界换取系统解码与显示能力，并使 Enchron 只面对单一播放契约。
