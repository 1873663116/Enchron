# Format Description 所有权重构报告

本次改动完成规格 F1 至 F5、G1 和 G2。构造仍在 C 侧，Swift 只提交 reader、AVFoundation 源格式或 presentation override 请求。五类真实文件所需的分支没有删除。

## 判据与证据

| 判据 | 结果 | 证据 |
|---|---|---|
| F1 | 已验证 | `normalize_mov_codec_ids` 只有一个静态调用点。所有 `avformat_find_stream_info` 路径都经过 `finalize_stream_information`。`verify_format_description_ownership.py` 返回 0。 |
| F2 | 已验证 | 唯一公开构造入口是 `PBFFmpegVideoFormatDescriptionCreate`。旧的 `PBFFmpegReaderCopyCompressedFormatDescription` 已删除。reader 构造、AVFoundation 保真合并和 presentation override 都调用该入口。容器无配置、Annex B 参数集、Dolby Vision 样本描述、像素长宽比补全和正常路径仍是 C 所有者的内部支路。 |
| F3 | 已验证 | `MediaSourceInformation` 现在持有容器是否支持源 Format Description、Dolby Vision profile、cross-compatibility ID、Dolby Vision enhancement layer 和 stereo video enhancement layer。`VideoSampleProviderInfo` 不再持有这些源事实。session 把同一个 `MediaSourceInformation` 交给视频、音频和字幕 provider；共享值测试通过。旧 JSON 缺少新键时按 `0` 或 `false` 解码。 |
| F4 | 已验证 | `shouldConsultAVFoundation` 只读取 supplied asset 和 `MediaSourceInformation.containerSupportsSourceFormatDescription`。函数内没有 `pathExtension`、容器名称或 MOV、MP4 后缀表。容器事实由 C demuxer 明确报告。 |
| F5 | 已验证 | `create_format_from_source` 先复制 AVFoundation extensions 和 decoder atoms，只用 bridge 中缺失的 `avcC`、`hvcC`、`lhvC`、`dvcC`、`dvvC` 或 `av1C` 补空位。`formatDescriptionOwnerFillsOnlyMissingDecoderConfigurationAtoms` 验证补缺；现有 camera-original、MV-HEVC、APMP 和 Dolby Vision 测试验证容器原文优先。公开头文件写明冲突规则和返回值所有权。 |
| G1 | 已验证 | 检查脚本进入 Enchron 和 DesignPreview 的 `Design Source Architecture` 构建阶段。正常 visionOS generic build 输出 `format-description structure check passed` 和 `BUILD SUCCEEDED`。临时加入 `pathExtension` 违规后，同一构建输出违规原因并以 65 退出；临时改动随后恢复。 |
| G2 | 已验证 | `ENCHRON_FORMAT_CHECK_ROOT=/tmp/ench-format-check-missing python3 Scripts/verification/verify_format_description_ownership.py` 以 2 退出，并打印缺失的 `PlaybackFFmpegBridge.c` 路径。 |
| V1 | 已验证 | 改动前和改动后各运行一次 107 文件的 `verify_source_parity_matrix.py --mode parity`。两个 JSON 的样本名相同；逐项比较本地与 HTTP 的 `codec`、`samples`、`sample_bytes`、`decoded_frames`、`submit_failures`、`callback_failures` 和 `decode` 后，差异为 0。两份规范化结果的 SHA-256 都是 `cf669d9ec9480ee6b019e6f4b48178080b91eadfa8d9208c29f7b54d2beda97c`。 |
| V3 | 已验证 | 改动前后失败名相同，均为 8 个失败和 13 个 issue。最终改动后运行执行 203 个测试，其中新增测试通过。 |

V3 的固定失败名如下：

- `appleMVHEVCFixtureIsDistinguishedFromOrdinaryHEVC`
- `appleImmersiveProviderClassifiesSourceWithoutReplacingMismatchedBridgeFormat`
- `controllerRejectsSecondOpenAndRecordsTheRejection`
- `rapidSeeksOnlyPublishCuesAtTheNewestCommittedPosition`
- `controllerSeekKeepsSessionAndAdvancesStreamEpoch`
- `newerSeekSupersedesOlderSeekAndOwnsFinalTarget`
- `threeRapidSeeksOnlyAllowNewestWaiterToEnterSession`
- `rapidRelativeSeeksAccumulateInsideTheCore`

一次相邻的改动前运行和一次相邻的改动后运行还出现了已记录的 `acceptedProResWithoutDisplayedFrameReportsRendererErrorVerbatim` 负载 flake。干净重跑均回到上述固定 8 个失败和 13 个 issue，因此没有把数量相同当作失败名相同的替代证据。

两次 V1 脚本都报告 97 个 `ok`、7 个 `not_video` 和 3 个既有非成功本地结果。两次也都有相同的 4 个 HTTP 超时差异，因此脚本各自以 1 退出，但都正常写出 JSON。V1 比较的是这些完整结果在改动前后是否逐字段一致，不把脚本的本地与 HTTP 差异隐藏成成功。

## 主要验证命令

```text
python3 Scripts/verification/verify_format_description_ownership.py
ENCHRON_FORMAT_CHECK_ROOT=/tmp/ench-format-check-missing python3 Scripts/verification/verify_format_description_ownership.py
swift build --package-path Packages/PlaybackCore --target PlaybackCore
swift test --package-path Packages/PlaybackCore
xcodebuild -project Enchron.xcodeproj -scheme Enchron -configuration Debug -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO build
python3 Scripts/verification/verify_source_parity_matrix.py --mode parity --output /tmp/ench-format-parity-before.json
python3 Scripts/verification/verify_source_parity_matrix.py --mode parity --scratch-path /Volumes/Cortisol/DevSpace/Xcode/Enchron/PlaybackCoreBuild-format-after-final --output /tmp/ench-format-parity-after.json
```

## 范围与代价

`Modules/MediaSource`、`Modules/MediaLibrary`、`Modules/Emby` 和 `Modules/PlaybackFeature` 没有改动。`PlaybackFFmpegBridge.c` 原始第 250 至 420 行范围没有 diff hunk，解封装读线程没有改动。

单一 C 入口用互斥的可空参数表达三种请求，并拒绝混合请求。代价是 Swift 调用必须显式传入未使用的 `nil`。这比保留 reader 专用的第二入口更容易做结构检查。

`MediaSourceInformation` 的新键会出现在新编码结果中。自定义解码保留旧编码结果的可读性。绕过 session 直接使用 FFmpeg video provider 时，provider 从已经打开的 reader 复制同一种 `MediaSourceInformation`，不会为格式判断再次打开媒体。

本 worktree 原本缺少被忽略的 FFmpeg binary artifact。验证时从主工作树复制了相同的 `PlaybackFFmpeg.xcframework` 到忽略路径；该文件不在提交和 `final-code.diff` 中。

## 未完成项

没有。F1 至 F5、G1、G2、V1 和指定的 V3 底线都已取得证据。
