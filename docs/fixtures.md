# Fixture 规范

PlaybackCore 的测试素材分为 contract、seed 和 restricted 三类。

| Class | Usage | Constraint |
|---|---|---|
| Contract | 常规 L1 / L2 自动化。 | 短小、许可清楚、metadata 稳定、可重复校验或生成。 |
| Seed | 真实媒体风险探索、手动 L2、L3、派生 contract fixture。 | 可较大或有瑕疵；风险进入本地 registry。 |
| Restricted | 版权、内容、来源或体积受限的本地样片。 | 不进入仓库 / CI；公开文档只写脱敏 ID。 |

当前 `/Users/xiongzhipeng/Desktop/test` 是本地 seed / restricted 来源，不是仓库 contract registry。本地 HDR10 已知观测点 `7.507500 s` 只用于人工定位，不作为可提交 fixture。

## Registry

仓库 registry 未来落在 `Tests/Fixtures/registry.json`。本地 registry 建议使用 `~/Desktop/test/fixture-registry.local.json`。每个条目至少记录：

```json
{
  "fixtureID": "short-sdr-h264-video-only",
  "path": "Tests/Fixtures/short-sdr-h264-video-only.mp4",
  "class": "contract",
  "repositoryAllowed": true,
  "ciAllowed": true,
  "sourceKind": "generated",
  "fileHash": "sha256:...",
  "container": "mp4",
  "codec": "h264",
  "codecTag": "avc1",
  "dimensions": "640x360",
  "durationSeconds": 3.0,
  "nominalFrameRate": 30.0,
  "colorPrimaries": "bt709",
  "transferFunction": "bt709",
  "yCbCrMatrix": "bt709",
  "range": "video",
  "hdrKind": "SDR",
  "expectedRoutes": {
    "appleCompressed": "supported",
    "ffmpegCompressed": "supported"
  },
  "expectedTimeline": {},
  "expectedMetadata": {},
  "generationCommand": "...",
  "verificationCommand": "...",
  "lastVerifiedAt": "..."
}
```

每条 route 的期望独立记录。`unsupported` 必须带单一预期错误，不能写成“失败或 fallback 都算通过”。

## 第一批 contract fixtures

1. 短 H.264 SDR MP4 video-only：关闭双路线公开 open、sample、renderer、displayed frame、seek、close / reopen。
2. 短 HEVC Main10 HDR10 video-only：关闭 compressed format、decoded attachments 与 HDR metadata provenance。
3. 含 B-frame 的 H.264 / HEVC：验证 PTS、DTS、duration 和 decode / presentation order 不被合并。
4. 明确 unsupported / malformed source：分别验证 Provider open failure 与 sample production failure。
5. 双 AAC 音轨 H.264 SDR MP4：由 `script/generate_multiaudio_fixture.sh` 重复生成，验证音轨枚举、选择、音频 enqueue，以及选择后音量、静音、倍速和 seek。

Dolby Vision Profile 5、8.1、8.4 当前是本地 seed / L3 fixtures。它们的 Apple Compressed 结果单独记录，不自动升级为公开 contract fixtures。

本地 `equirect_grid_hevc_mono_30s_apmp.mov` 由 Apple 官方 “Converting projected video to Apple Projected Media Profile” 示例从生成的 2:1 HEVC seed 转换而来。CoreMedia 必须读到 `ProjectionKind = Equirectangular` 后，它才可用于 Panorama / Portal 投影验证；只有 2:1 画幅而没有 APMP `vexu` 信令的文件不算投影 fixture。

## Route-specific assertions

Apple Compressed 检查 storage-format sample、media subtype、sample-description atoms、timing 与 color / HDR extensions。FFmpeg Compressed 检查 packet ownership、compressed format description、codec configuration、sync attachment 与 timing。

## 自动化准入

fixture 进入自动化前必须有稳定 hash、许可或来源说明、完整 video stream 读取、无持续 renderer failure、明确 route expectations、生成 / 验证命令和最近一次验证结果。短视频用于可见帧或截图时，测试必须显式处理 ended 或 loop，不能依赖视频尚未自然结束。
