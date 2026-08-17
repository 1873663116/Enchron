# Format Description 恒等清零与门禁接入报告

## 结论

本次改动已完成格式描述恒等清零，并把 `verify_format_description_identity.py` 与 `verify_glass_usage.py` 接入验证门禁。完整门禁、源一致性检查和 visionOS 整机构建均通过。本次工作没有使用物理设备。

分支为 `work/identity-zero`，基线提交为 `4e0cc7e0`。验证使用 Xcode 27.0 beta 5，构建版本为 `27A5237l`，active developer directory 为 `/Volumes/Cortisol/Applications/Xcode-beta5.app/Contents/Developer`。

## 构造修复

非 Annex-B H.264 现在从 `avcC` 中提取 SPS 与 PPS，并通过 `CMVideoFormatDescriptionCreateFromH264ParameterSets` 创建基础格式描述。构造入口随后合并原有扩展。CoreMedia 因此可以展开 SPS 中的色彩和 range 声明。

色彩扩展映射还将 FFmpeg 的 `AVCOL_TRC_IEC61966_2_1` 映射到 `kCMFormatDescriptionTransferFunction_sRGB`。恒等检查的期望模型使用 CoreMedia 实际公开的 `IEC_sRGB` 值。该映射修复了只读审查发现的一项原有静默漏检。

该修复处理了四个原有差异文件：

- 两个 Apple 相机原片现在携带 limited range。
- Sony A7S III 原片现在携带 full range。
- SDR 行为向量现在携带 BT.709 primaries、transfer、matrix 和 limited range。
- Apple `applle.MOV` 现在携带已声明的 IEC 61966-2-1 transfer。

改动位于 `PlaybackFFmpegBridge.c` 的 H.264 格式构造区域。音频区域未改动。

## 显式裁决

`Config/format_description_identity_baseline.json` 按声明形状记录豁免和能力边界。规则不使用文件名。每条规则包含理由、依据和固定计数。匹配总数变化、未分类差异和重复匹配都会使检查失败。检查会逐文件打印实际匹配；同一声明形状下等量替换文件不会触发计数漂移，这是禁止文件名特判后的明确限制。

| 类别 | 声明形状 | 计数 | 裁决依据 |
| --- | --- | ---: | --- |
| 豁免 | ProRes，`color_range=tv`，期望 `full_range=0`，实际无扩展 | 8 | CoreMedia 将 YCbCr 压缩格式缺少 `FullRangeVideo` 定义为 limited range。 |
| 豁免 | ProRes，`color_space=bt709`，期望 matrix，实际无扩展 | 5 | ProRes matrix 来自逐帧压缩 header。CoreMedia 的流级源格式描述不提升该逐帧值。 |
| 豁免 | H.264 未声明 range，CoreMedia 实际物化 `full_range=0` | 1 | H.264 parameter-set 构造函数物化平台规定的 limited-range 默认值。 |
| 能力边界 | `codec_name=prores_raw`，错误形状精确匹配 | 1 | 当前设备不支持 ProRes RAW 压缩样本渲染。 |
| 能力边界 | `codec_name=mpeg4`，错误形状精确匹配 | 1 | 当前设备不支持 MPEG-4 Part 2 压缩样本渲染。 |

裁决依据可按以下入口复查：

- Xcode beta5 的 `XROS27.0.sdk/System/Library/Frameworks/CoreMedia.framework/Headers/CMFormatDescription.h` 在 `kCMFormatDescriptionExtension_FullRangeVideo` 定义处说明，YCbCr 压缩格式缺省值为 false，即 video range。该 header 还将 `kCMFormatDescriptionTransferFunction_sRGB` 关联到 CoreVideo 的 sRGB 常量。
- FFmpeg 的 [`decode_frame_header`](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/proresdec.c#L174-L266) 从 ProRes 帧 header 的字节 14 至 16 读取 primaries、transfer 和 matrix，并将 range 设为 MPEG range。完整语料输出同时记录 CoreMedia 流级格式描述没有提升五个 FATE ProRes 样本的逐帧 matrix。
- H.264 未声明 range 的默认值、ProRes 流级省略结果和两项能力拒绝均来自实际探针输出。检查现在将对应依据与理由一起打印。

恒等检查终态如下：

```text
SUMMARY files=118 dolby_vision_pass=19 dolby_vision_fail=0 unclassified=0 baseline_drift=0 capability-boundary=2 exemption=9 no-video=10 pass=97
```

其中 10 个文件没有视频声明，检查将其作为恒等命题不适用但通过的结果显示。所有豁免和能力边界均在标准输出中显示理由。

## 门禁分层

完整门禁的结构检查从 7 项增加到 9 项。`verify_glass_usage.py` 同时进入 quick 和完整模式。`verify_format_description_identity.py` 只进入完整模式，因为它依赖仓库外的 `TestMedia`，需要构建探针并扫描 118 个媒体文件。quick 模式现在执行 8 项结构检查，完整模式执行 9 项。

## 验证结果

完整门禁命令为：

```text
python3 Scripts/verification/run_verification_gauntlet.py
```

最终提交上的完整门禁通过。日志目录为 `/Volumes/Cortisol/DevSpace/Xcode/Enchron/VerificationGauntlet/runs/20260817T062839Z-36703`。结果如下：

- 9 项结构检查全部通过。
- PlaybackCore 完成 213 项测试。以下三个既知失败名称与基线精确匹配：`appleMVHEVCFixtureIsDistinguishedFromOrdinaryHEVC`、`appleImmersiveProviderClassifiesSourceWithoutReplacingMismatchedBridgeFormat`、`controllerRejectsSecondOpenAndRecordsTheRejection`。
- `acceptedProResWithoutDisplayedFrameReportsRendererErrorVerbatim` 本次通过，没有触发偶发超时重跑。
- parity 检查处理 110 个媒体结果，传输差异为 0，三个既知媒体状态与基线精确匹配。
- feature evidence coverage 和 guard self-tests 均通过。

基础设施单元测试共 11 项，全部通过：

```text
python3 -m unittest Tests/Infrastructure/test_format_description_identity.py Tests/Infrastructure/test_verification_gauntlet.py
```

visionOS 整机构建命令为：

```text
xcodebuild -project Enchron.xcodeproj -scheme Enchron -configuration Debug -destination 'generic/platform=visionOS' -derivedDataPath /Volumes/Cortisol/DevSpace/Xcode/Enchron/DerivedData/IdentityZero -clonedSourcePackagesDirPath /Volumes/Cortisol/DevSpace/Xcode/Enchron/SourcePackages/IdentityZero CODE_SIGNING_ALLOWED=NO build
```

构建结果为 `BUILD SUCCEEDED`。产物位于 `/Volumes/Cortisol/DevSpace/Xcode/Enchron/DerivedData/IdentityZero/Build/Products/Debug-xros/Enchron.app`。

## 提交

- `fed32c22 Preserve H.264 SPS color declarations`
- `7abc348c Classify format identity outcomes by declaration`
- `717124ab Add identity and glass checks to the gauntlet`
- `d651805e Preserve declared sRGB transfer functions`
- `50fc21f1 Expose identity decision evidence`

`final-code.diff` 是上述五个代码提交相对 `4e0cc7e0` 的零上下文完整文本差异，可通过 `git apply --unidiff-zero` 应用。分支未推送。
