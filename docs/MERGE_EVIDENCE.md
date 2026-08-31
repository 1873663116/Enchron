# 合并证据与授权

本文定义 Enchron 的合并证据强度、语义改动分类、授权裁决和 RunReceipt。`Scripts/rules/merge_evidence_tier.py` 计算证据 Tier，`Scripts/rules/merge_authority.py` 生成并复验合并授权凭据。两项职责相互独立。

## 两个正交维度

Tier 只回答“需要多强的实测证据”。ChangeKind 只回答“机器是否有权在证据充分后判定可自动合并”。W0 不表示低风险或自动授权，W3 也不自动表示必须人审。

| ChangeKind | W0 | W1 | W2 | W3 |
|---|---|---|---|---|
| `behavior-preserving-refactor` | 证据充分后 `AutoMergeEligible` | 同左 | 同左 | 同左 |
| `bug-fix` | 证据充分后 `AutoMergeEligible` | 同左 | 同左 | 同左 |
| `new-feature` | `HumanReviewRequired` | 同左 | 同左 | 同左 |
| `regression-contract` | `HumanReviewRequired` | 同左 | 同左 | 同左 |
| `public-api` | `HumanReviewRequired` | 同左 | 同左 | 同左 |
| `module-ownership` | `HumanReviewRequired` | 同左 | 同左 | 同左 |
| `persistence` | `HumanReviewRequired` | 同左 | 同左 | 同左 |
| `core-domain-model` | `HumanReviewRequired` | 同左 | 同左 | 同左 |

一个范围可以声明多个 ChangeKind。只要其中一个属于人审类别，整个范围就是 `HumanReviewRequired`。ChangeKind 是闭合枚举；未声明语义改动或传入未知值时，授权工具拒绝生成 RunReceipt。

证据 Tier 只有 W0、W1、W2、W3。不存在 W4。

## Tier 与路径分类

一个 commit 范围采用其中最高的路径 Tier。映射外的路径归入 W3。前缀按最长匹配，因此 `Packages/PlaybackCore/Tests/` 属于 W1，不会落入包本体的 W3。

| 前缀 | Tier |
|---|---|
| `docs/`、`.agents/skills/` | W0 |
| `Regression/`、`Scripts/`、`Config/`、`Tests/`、`Packages/PlaybackCore/Tests/` | W1 |
| `Modules/DesignSystem/`、`Modules/Emby/`、`Modules/MediaLibrary/`、`Modules/MediaSource/` | W2 |
| `Packages/PlaybackCore/`、`Apps/Enchron/`、`Modules/Playback/`、`Packages/RealityKitContent/` | W3 |
| 其他路径 | W3 |

各 Tier 的最低证据如下。

| Tier | 必需证据 |
|---|---|
| W0 | verification 的 `summary.json`，且 `verdict` 为 `passed` |
| W1 | 与 W0 相同 |
| W2 | W1 加模拟器端到端产物 |
| W3 | W2 加 Device Hub 真实输入产物；纯解码能力改动可用真机解码产物替代模拟器与 Device Hub 产物 |

Device Hub 产物目录必须包含可解析的 `diagnostics.json`，并包含 App 侧 `spatialTap entity=<entity> ... accepted=true` 探针行。工具读取产物内容后再决定证据是否成立，不能用一条手写 JSON 声称它们存在。

真机解码特例必须包含 JSON 结果。该结果需要非空的 `capability`，并以 `passed: true` 或 `verdict: "passed"` 明确记录结果。

## RunReceipt

旧的 evidence manifest v1 已移除，没有兼容入口。工具不接受 `--manifest`，也不读取由提交者手写的证据指针清单。

生成 RunReceipt 时，调用方只传入 commit 范围、ChangeKind 和实际产物路径。工具完成以下绑定：

```text
commit range ──> base/head OID + binary diff SHA-256
changed paths ─> 逐路径分类 + Tier
ChangeKind ────> AuthorityDecision
artifacts ─────> 仓库相对路径 + 每个文件的字节数和 SHA-256
runtime ───────> 工具及探针谓词 SHA-256 + Python/Git/Xcode/OS/DEVELOPER_DIR 身份
approval ──────> 审批凭据路径 + 当前字节 SHA-256
```

RunReceipt 使用 `enchron.merge-run-receipt/v1` schema。JSON 键按字典序输出，使用固定缩进并以换行结束；同一工具、环境、范围、声明和产物必然生成相同字节。

复验会重新解析符号范围、读取当前 diff、重新分类、重新读取全部产物并重算身份。下列情况均以非零退出码拒绝：

- 符号范围的 HEAD 或上游已经移动；
- diff、证据文件、审批凭据或工具文件被修改；
- 当前工具环境与生成环境不同；
- 证据低于当前 Tier；
- 没有 ChangeKind 声明；
- `HumanReviewRequired` 缺少与当前范围及声明完全一致的 approval receipt；
- RunReceipt 不是规范化 JSON，或其中任何派生字段被手工修改。

## 生成与复验

以下示例为 W2 的行为保持重构。证据路径可以指向单个文件或目录；目录内的每个普通文件都会单独绑定。

```sh
python3 Scripts/rules/merge_authority.py generate origin/main..HEAD \
  --change-kind behavior-preserving-refactor \
  --evidence verification-green=.scratch/Verification/runs/<run>/summary.json \
  --evidence simulator-e2e=.scratch/e2e/<run> \
  --output .scratch/merge/run-receipt.json

python3 Scripts/rules/merge_authority.py verify \
  --receipt .scratch/merge/run-receipt.json
```

证据不足时不会写出 RunReceipt。`AutoMergeEligible` 仅表示当前 ChangeKind 允许机器在全部证据成立后授予自动合并资格；它不绕过仓库的其他检查。

## 显式审批凭据

`HumanReviewRequired` 必须先生成 approval receipt。审批凭据绑定当前 range、base/head OID、diff 哈希、逐路径分类、Tier、全部 ChangeKind、裁决、审批主体和外部审批引用。它没有全局通配能力，也不能移用到另一个 HEAD。

```sh
python3 Scripts/rules/merge_authority.py approve origin/main..HEAD \
  --change-kind module-ownership \
  --authority reviewer@example.com \
  --reference decision://merge-governance-cutover \
  --output .scratch/merge/approval.json

python3 Scripts/rules/merge_authority.py generate origin/main..HEAD \
  --change-kind module-ownership \
  --evidence verification-green=.scratch/Verification/runs/<run>/summary.json \
  --evidence simulator-e2e=.scratch/e2e/<run> \
  --evidence device-hub-input=.scratch/device-hub/<run> \
  --approval .scratch/merge/approval.json \
  --output .scratch/merge/run-receipt.json
```

已经获得人工批准、但证据尚未跑完的改动可以先保存 approval receipt，待产物齐备后再生成 RunReceipt。审批不能降低 Tier，也不能代替缺失证据。对于 `AutoMergeEligible` 的改动，`--approval` 是可选项；若本次改动已经人工批准，仍可附加同样的 approval receipt，使批准事实与最终 RunReceipt 一起绑定。

## verification 中的分类器

`run_verification.py` 无参数运行 `merge_evidence_tier.py`，只把范围分类和所需证据写入 structure 日志。该步骤不生成授权，也不把任何 Tier 翻译为自动合并资格。真正的合并授权来自 `merge_authority.py generate` 产出的 RunReceipt，并以 `verify` 的成功复验为准。
