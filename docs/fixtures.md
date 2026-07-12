# 测试素材

这里规定播放核心测试素材的分类和 registry schema，作为 `core-spec.md` 与 `acceptance/verification-system.md` 的附件。

## 分类

| 类型 | 用途 | 约束 |
|---|---|---|
| Contract fixtures | 常规 L1 / L2 自动化。 | 短小、可公开或许可清楚、metadata 明确、可重复生成或校验、解码无持续错误日志。 |
| Seed fixtures | 探索真实媒体风险、手动 L2 冒烟、L3 真机观察、生成 contract fixture 的来源。 | 可以较大或带真实世界瑕疵；风险必须记录在本地 registry。 |
| Restricted fixtures | 受版权、内容敏感性、体积或来源限制的本地样片。 | 不进入仓库，不进入持续集成，不在公开文档中描述内容细节。 |

重编码生成的样本可以成为 contract fixture。每个重编码 fixture 必须记录源文件、生成命令、输出 metadata 和限制。

## 第一条 vertical slice 素材

第一条 vertical slice 使用最小 contract fixture。它可以复用已有 test 视频，也可以由 seed fixture 重编码生成；
只有被登记、校验并满足以下条件后，才能关闭第一条端到端 slice。

- 短小，适合 L1 / L2 常规自动化。
- 文件可公开或许可清楚，允许进入仓库或明确记录为本地 contract fixture。
- container 为 MP4 或 MOV。
- codec 为 H.264 Baseline 或 Main。
- 只有一个 video track。
- 没有 audio track。
- 没有 subtitle track。
- projection 为 `rectilinear`。
- stereoLayout 为 `mono`。
- 不含 HDR / EDR 目标 metadata。
- 不含 Apple 空间视频、Multiview High Efficiency Video Coding (MV-HEVC)、Apple Immersive Video、DRM 或受保护内容。
- metadata 能用 `ffprobe` 稳定读出。
- 有稳定 `fixtureID`、`fileHash`、来源、验证命令和最近一次验证结果。

已有 test 视频如果满足这些条件，可以直接登记为第一条 contract fixture。否则在实现时生成一个最小 H.264
video-only fixture，并记录生成命令与验证命令。

## Registry 分层

仓库只记录公开规则、schema、contract fixture logical id 和可公开元信息。受限素材的真实路径、内容描述和完整 artifact 只进入本地 registry。

推荐本地 registry：

```text
~/Desktop/test/fixture-registry.local.json
```

未来仓库 registry 可以落在：

```text
xr-fork/core/Tests/Fixtures/registry.json
```

## Fixture 字段

每个 fixture 条目至少包含：

```json
{
  "fixtureID": "hlg-gray-ramp-sequence",
  "path": "/absolute/or/repo/relative/path",
  "class": "contract",
  "repositoryAllowed": true,
  "ciAllowed": true,
  "documentationAllowed": true,
  "sourceKind": "derived",
  "sourceFixtureID": "hlg-patch-set",
  "licenseOrRestriction": "public or local-only note",
  "containerFormat": "mov,mp4,m4a,3gp,3g2,mj2",
  "codec": "hevc",
  "profile": "Main 10",
  "bitDepth": 10,
  "chromaFormat": "yuv420",
  "colorPrimaries": "bt2020",
  "transferFunction": "arib-std-b67",
  "ycbcrMatrix": "bt2020nc",
  "hdrKind": "HLG",
  "fileHash": "sha256:...",
  "expectedAudioTracks": [],
  "expectedSubtitleTracks": [],
  "subtitleCues": [],
  "expectedMetadata": {},
  "projection": "rectilinear",
  "stereoLayout": "mono",
  "scannerGroundTruthProjection": "rectilinear",
  "scannerGroundTruthStereoLayout": "mono",
  "scannerAllowedOutcomes": ["rectilinear+mono"],
  "testUsage": ["L1 metadata", "L2 visual", "L3 EDR observation"],
  "knownRisks": ["reencoded"],
  "excludedFormat": null,
  "expectedError": null,
  "generationCommand": "ffmpeg ...",
  "verificationCommand": "ffprobe ...",
  "lastVerifiedAt": "2026-06-28",
  "lastVerificationSummary": "hevc Main 10, bt2020nc/arib-std-b67/bt2020"
}
```

字段规则：

- `fixtureID` 是稳定逻辑标识，不随文件名变化。
- `class` 取 `contract`、`seed` 或 `restricted`。
- `repositoryAllowed`、`ciAllowed` 和 `documentationAllowed` 分别说明仓库、持续集成和公开文档可用性。
- `fileHash` 用于判断证据是否仍指向同一素材。
- `expectedAudioTracks` 和 `expectedSubtitleTracks` 是轨道 ground truth。
- `subtitleCues` 至少记录时间点，并记录 `expectedText` 或 `overlayDigest`。
- `projection` 取 `rectilinear`、`halfEquirectangular`、`equirectangular`、`fisheye` 或 `unknown`。
- `stereoLayout` 取 `mono`、`sideBySide`、`overUnder` 或 `unknown`。
- Apple 空间视频和 Multiview High Efficiency Video Coding (MV-HEVC) 不作为 `stereoLayout`，用 `excludedFormat` 或 `expectedError` 表达。
- High Dynamic Range (HDR) / Color L1 fixture 必须填写 `expectedMetadata`。

## HDR / Color metadata

HDR / Color contract fixture 的 `expectedMetadata` 至少分层记录：

- `bitstream`：color primaries、transfer function、YCbCr matrix、mastering display color volume、content light level、ambient viewing environment、Dolby Vision config、dynamic metadata presence。
- `container`：`colr`、`mdcv`、`clli`、`amve`、`dvcC`、`dvvC` 等盒子或等价字段是否存在。
- `runtime`：期望进入 `CMFormatDescription` extension 与 `CMSampleBuffer` attachment 的字段。
- `final`：`hdrKind`、`metadataConflictStatus`、`finalMetadataSource`。

当前压缩硬解路径不持有 decoded pixel buffer，`runtime.pixelBufferAttachments` 通常为 `notAvailable`。

## Codec coverage matrix

仓库 registry 或未来 `core/Tests/Fixtures/registry.json` 必须维护 codec coverage matrix。矩阵不靠文档手写猜测硬件能力；实现期通过 AVFoundation / VideoToolbox capability probe 生成候选，再由 fixture 绑定测试证据。

每行至少包含：

| 字段 | 说明 |
|---|---|
| `codec` | `h264`、`hevc`、`dolbyVisionHEVC`、`proRes` 等能力 probe 返回或项目显式负向测试的 codec id。 |
| `profile` / `level` / `bitDepth` / `chromaFormat` | L1 要断言的 codec config。 |
| `containerFormat` | MP4、MOV、MPEG-TS 等。 |
| `supportStatus` | `supportedHardware`、`unsupportedCodec`、`deferred`、`excludedFormat`。 |
| `deviceGeneration` / `supportScope` | `M2`、`M5`、`allVisionPro`、`M5-only` 等设备范围。 |
| `positiveFixtureID` | 支持路径 fixture。没有时不得宣称该行已覆盖。 |
| `negativeFixtureID` | unsupported / excluded 路径 fixture。 |
| `l1Assertions` | format description、sample builder、metadata 等断言。 |
| `l2Evidence` / `l3Evidence` | 模拟器或真机证据路径，可为空但必须存在字段。 |

进入 L3 前，所有 `supportedHardware` 行必须至少有 L1 证据；硬件真实解码仍由 L3 验收。

## 自动化准入

素材进入自动化前必须满足：

- 文件可公开或许可清楚。
- 文件体积适合常规测试。
- metadata 稳定。
- 能用 `ffprobe` 稳定读出关键字段。
- 解码不产生持续错误日志。
- 有明确测试用途。
- 有 fixture id、来源、验证命令和最近一次验证结果。

短视频用于 L2 截图和视觉断言时，验证 App 必须开启 loop playback。自动化不能依赖视频尚未自然结束这一偶然条件。
