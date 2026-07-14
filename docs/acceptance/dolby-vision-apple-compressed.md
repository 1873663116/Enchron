# Apple Compressed Dolby Vision 验收

Apple Compressed 使用 `AVAssetReaderTrackOutput(outputSettings: nil)` 输出 storage-format compressed `CMSampleBuffer`，不经过 decoded pixel buffer、pixel transfer 或 sample 重建。

## Profile 5

Fixture：`Patterns_Of_Nature_DoVi_24_P5_UHD_HEVC-10mbps_DD+JOC-768kbps_iOS.mp4`

唯一预期结果：Vision Pro 上的 Apple Compressed 画面与系统播放器一致。

已证明：macOS probe 保留 `dvh1 + hvcC + dvcC`，renderer 无错误并产生 displayed pixel buffer。

Vision Pro：已验收，画面与系统播放器一致。

## Profile 8.1

Fixture：`Patterns_Of_Nature_HDR10-P8.1_UHD_24_H265-10Mbps_DD+JOC-768Kbps.mp4`

唯一预期结果：Vision Pro 上的 Apple Compressed 画面与系统播放器一致。

已证明：macOS probe 保留 `hvc1 + hvcC + dvvC`，renderer 无错误并产生 displayed pixel buffer。

Vision Pro：已验收，画面与系统播放器一致。

## Profile 8.4

Fixture：`Patterns_Of_Nature_HLG-P8.4_UHD_24_H265-10Mbps_DD+JOC-768Kbps.mp4`

唯一预期结果：Vision Pro 上的 Apple Compressed 画面与系统播放器一致。

已证明：macOS probe 保留 `hvc1 + hvcC + dvvC`，renderer 无错误并产生 displayed pixel buffer。当前 fixture 本身不含 `amve`。

Vision Pro：已验收，画面与系统播放器一致。
