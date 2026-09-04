# 回归 Harness 工具化

## 背景

当前回归系统有两层：合同与编译层（`Regression/` 与 `Scripts/regression/core/`）产出不可变 RunPlan，流程层（`Scripts/regression/runctl.py` 的 `run` 子命令、`Scripts/regression/sidekick_runner.py`、`Scripts/regression/oracle_agent.py`、`Scripts/verification/run_campaign.py`）负责把这份计划跑完。流程层从未跑出过一次完整回归。它的唯一消费者是自己的自测：`Scripts/rules/test_campaign_launcher.py` 是 `Scripts/verification/run_campaign.py` 的唯一导入方，`.github/workflows/verification.yml` 只运行 `Scripts/rules/run_verification.py`。

流程层的代价是具体的：`Scripts/regression/sidekick_runner.py` 1205 行加上 1657 行自测，`Scripts/regression/oracle_agent.py` 340 行加上 230 行自测，全部用于维持一个「跑完一组」的入口。而实际调试与取证一直由交互中的 Agent 逐条驱动 `Scripts/verification/interactive_visionpro_ui.py` 完成。

判读侧同样有缺口。`Regression/oracle-protocol.md` 写明当前 Catalog 没有实现字段谓词的确定性运行时 Oracle，97 份 rubric 全部是自然语言 criteria，每一条 obligation 的判定都要一次 Agent 调用。

失效粒度过粗。`Scripts/regression/core/plan.py:318` 的 `EvidenceEnvironmentIdentity` 只有一个全局 `deterministic_runtime_digest`，任何一处 harness 修复都会让全部既有证据失效。

## 范围

以下十节是已达成共识的设计，逐字保留。

### 架构

Harness 是一组工具，每个工具在设备上做一件事并把证据带回来。没有"跑完一组"的入口。循环只存在于交互中的 Agent 和 console 前的人。

工具以 MCP 暴露；异常包以 image 内容块随返回值进入 Agent 上下文。

### 工具集

| 工具 | 做什么 | 返回 |
|---|---|---|
| session | ensure / halt；`--mode human` 时开录屏、起 console、轮询时间线 | stage |
| op | 执行编译计划中的一个 Operation Call，跑 L0 字段谓词与 L1 像素启发 | verdict、结构化字段、截图（image） |
| bundle | 异常包：前后帧、录屏抽帧拼图、关键区域裁切、字段 diff、命中签名 | image + JSON |
| ledger | 写裁决、查状态、续跑点 | 账本视图 |
| receipt | 从账本算合并收据 | 收据或拒绝理由 |

### 护栏：账本锁

某 lane 出现非 Satisfied 后，该 lane 的下一次 op 被拒绝，直到 ledger 收到裁决。裁决字段：首个偏离帧序号、裁切区域观察、归因 product|harness|spec、签名 id。序号超出拼图帧数即无效。绿色步骤不设锁。

### 判读三级

- L0 字段谓词：由 rubric 编译器从 97 份 rubric 生成，覆盖报告列出编不出的 criterion。
- L1 像素启发：1×1 捕获失败、全黑、帧差。
- L2 Agent：只在异常包之后，做归因。

### 人类层

静态为空。成员为账本终态 `deferred(human)` 的节点。入口条件由 ledger 校验：同一节点连续两次 attempt 的 op 结果均为 harness 超时类（transport-timeout、response-timeout、readyTimeout、ensure-session 未 ready）。产品慢是 Violated，不可推迟。

人类回归：session --mode human；console 打印从 deferred 列表生成的 checklist（人可扩大范围），每 2–3 秒轮询 snapshot --no-screenshot、控制面字段、PlaybackCore live json 写 timeline.jsonl，接受 mark 打标；人点完后用自然语言描述；halt 取回录屏；Agent 按 checklist 顺序与时间线对齐描述，抽帧，出归因；产出人类收据（checklist digest、build digest、device id、录屏 digest、逐条归因）。

### 收据

任一 tier 的节点要么由 Agent 账本关闭，要么由覆盖该节点 id 的人类收据关闭。W3 = 真机 lane 节点全部关闭，由谁关闭不限。path→tier 重切：Apps/Enchron/Screens/、Modules/MediaLibrary/ 归 W2。

### 失效粒度

EvidenceEnvironmentIdentity 的全局 deterministic_runtime_digest 改为逐 Operation 实现 digest。H 类修复只失效用过该 Operation 的节点。Scenario 层已知缺陷账本，failed(known) 不阻塞收据。

### 录屏

模拟器：simctl io recordVideo 按 Scenario 分段，异常时即时抽帧。真机：XCTest 会话录屏，halt 后取回，异常包在会话结束后生成。

### 删除

- runctl.py 的 run 子命令与 _run_full
- sidekick_runner.py、MainAgentCoordinator、lease
- oracle_agent.py、AgentOracleProvider
- run_campaign.py、test_campaign_launcher.py
- vp-e2e skill "不许中途收工"一节
- 真机无密码：diagnostics.md 第 9、10 行（锁定、授权），interactive_visionpro_ui.py 的 AUTOMATION_AUTHORIZATION_SIGNATURE（:931）与 authorizationTimeout 分支（:1441-1450、:1577）

### 注释规则

verify_product_source_comments.py 扩到 Scripts/**/*.py，清 307 行（regression 22、verification 161、rules 124）。

上面这一节的行数是设计定稿时的计数。规则扩容后实测 289 条（`Scripts/regression/` 22、`Scripts/rules/` 116、`Scripts/verification/` 151），本 PR 已全部清空：`python3 Scripts/rules/verify_product_source_comments.py` 报「182 product Swift files and 263 harness Python files contain no source comments」并以 0 退出。

### 明确排除

- 不新增 Journey、Scenario、Promise 或 rubric。97 份 rubric 的文本不改，编译器只读它们。
- 不改产品 Swift 源码。**偏离**：`Packages/PlaybackCore` 的 `PlaybackDebugRecorder.record` 与 `SampleBufferPlaybackSession+Diagnostics` 两处改了。前者的 `queue.sync` 与 MediaToolbox 构成锁序倒置，CI 上挂死 11 分钟，用 `sample(1)` 取到栈后改成 `queue.async`；后两处 `recordFailure` 与 `publishRendererFailure` 在写失败记录之前就发布了 `.failed`，读方拿到的是空记录。三处都是产品缺陷经由 harness 暴露，按「产品问题优先于 harness 问题」处理。
- 不动 `Scripts/rules/merge_authority.py` 的 RunReceipt 与 approval receipt 机制。`docs/MERGE_EVIDENCE.md` 中 Tier 与 ChangeKind 两个正交维度的划分保持原样，本计划只重切 path→tier 的前缀表。
- 不动 `Scripts/verification/harness/` 的预算体系（`budgets.py`、`provisional_budgets.json`、`controller_timings.device.json`、`controller_timings.simulator.json`、`fold_timing_samples.py`）。人类层的入口条件读取超时类故障 kind，不改变预算如何折算。
- 不动 `Scripts/verification/harness/parallel.py`。它的 campaign 形状拒绝逻辑被 `Scripts/verification/reachability_matrix.py:8127` 的 `_campaign_serial_refusal` 使用。
- 不实现真机分段录屏。真机沿用 XCTest 会话录屏，`halt` 之后由 `Scripts/verification/extract_visionpro_ui_recording.py` 从 `.xcresult` 抽帧。

## 约束

- 平台：macOS，visionOS 模拟器与 Apple Vision Pro 真机两条 lane。Python 3 标准库；Catalog 解析只用标准库 `json`，不引入 PyYAML（`Regression/README.md`）。
- 静态门：`Scripts/rules/run_verification.py` 的 `STRUCTURE_CHECKS` 表登记 47 项检查，并自动发现 `Scripts/rules/` 与 `Scripts/verification/` 下的全部 `test_*.py`。新增自测不需要登记；新增 `verify_` 或 `check_` 前缀的检查器必须登记，且受 Mutation Coverage Mandate 约束（`docs/CONTEXT.md`）。
- `Scripts/rules/verify_scripts_inventory.py` 按语法树给 `Scripts/` 下每个脚本分类，并要求文件名与分类一致、文件名在仓库别处被引用。新增工具脚本必须在文档或调用方中出现名字，否则该检查失败。
- `Scripts/rules/verify_product_source_comments.py` 覆盖 `Scripts/**/*.py`。本计划新增的每一个 Python 文件都不得含注释；解释写进类型、常量名或本目录下的计划文件。
- `Config/harness_primitives_allowlist.json` 登记允许直接驱动设备的脚本。删除或新增此类入口必须同步该文件，`Scripts/rules/harness_primitives_gate.py` 校验它。
- 模拟器的 `xcrun simctl io` 输出必须写进 `TMPDIR`。写仓库内路径会被拒为 `Operation not permitted`（`.agents/skills/vp-e2e/references/simulator.md`）。
- `Scripts/verification/interactive_visionpro_ui.py` 的 `ensure-session` 需要 `--execution-input` 或 `ENCHRON_EXECUTION_INPUT`，输入由 `python3 Scripts/regression/runctl.py freeze` 冻结。
- 真机没有密码。授权超时分支与相关的分流表行按设计删除。

## 方案比选

### 流程层的去留

- 甲，保留 `runctl run` 与 Sidekick 调度，在其上加一层 MCP 适配。既有 2862 行调度与自测继续维护，MCP 只是壳。Agent 仍然拿不到单步的返回值，异常包无法在调用点进入上下文。
- 乙，删掉流程层，工具直接以 MCP 暴露，循环交给交互中的 Agent 与 console 前的人。既有的编译层、能力白名单、gateway 授权与 ledger 全部保留，被工具复用。
- 丙，双轨：流程层做批量，另建一套工具供交互调试。两套入口对同一台设备的独占 runner 竞争，`ensure-session` 的单 runner 约束（`.agents/skills/vp-e2e/references/diagnostics.md`）使它们无法同时存在；两套代码对 ledger 的写入语义也会分叉。

选乙。流程层从未产出过一次完整回归，删除它不损失任何已经取得的证据。它的三份自测合计 2073 行，占 `Scripts/rules/` 自测总量 45930 行的 4.5%，每次静态门都在跑。丙的双写 ledger 风险与设备独占约束直接冲突。

### 判读的分层

- 甲，把 97 份 rubric 全部改写为确定性字段谓词。rubric 的 criteria 引用像素、时序与跨调用的 interactionTrace 对齐，相当一部分无法表达为字段比较，改写会削弱判据。
- 乙，维持全部由 Agent 判读的现状。每条 obligation 一次模型调用，判读不可复现，`Regression/oracle-protocol.md` 已经写明这一点不能称为确定性。
- 丙，三级：编译器把能编的 criterion 编成字段谓词（L0），编不出的进覆盖报告；像素级的失败签名走固定启发（L1）；Agent 只在异常包之后做归因（L2）。

选丙。它不要求 rubric 文本改动，编不出的部分由覆盖报告显式记账，与 `docs/CONTEXT.md` 的 Unguarded Evidence Point 是同一种处理方式：不假装覆盖，逐项列出。

## 适用技能

- **how**：改动 `Scripts/regression/core/` 的 plan、runtime、replay 之前，先走读该子系统。`Scripts/regression/core/runtime.py` 2303 行，`Scripts/regression/core/plan.py` 1425 行，`Scripts/regression/completion.py` 2997 行，任何一处的隐式约束都会在编译门上以类型错误出现。
- **architect**：阶段 7 到阶段 12 引入 MCP 工具集这一新的对外形状，工具边界与 `Scripts/regression/core/` 的既有公开接口如何分工由该技能定型。
- **interrogate**：阶段 8 的账本锁与阶段 15 的已知缺陷账本改变「什么情况下允许继续跑」，合并前对抗式审查。
- **unslop**：每个 commit 之前，以及本计划触及的每一份自然语言文档（`docs/MERGE_EVIDENCE.md`、`docs/CONTEXT.md`、`Regression/README.md`、`Regression/oracle-protocol.md`、`.agents/skills/vp-e2e/`）。
- **no-comments**：本计划新增的全部 Python 文件。`Scripts/rules/verify_product_source_comments.py` 已覆盖 `Scripts/**/*.py`，违反即静态门变红。
- **show-me-your-work**：19 个阶段跨越删除、新建与语义重切，决策链需要可审计记录。
- **technical-writing**：阶段 19 的文档同步。`docs/CONTEXT.md` 的术语表与 `docs/MERGE_EVIDENCE.md` 的 Tier 表是被其他文档引用的权威源。
- **writing-for-agents**：阶段 19 修改 `.agents/skills/vp-e2e/SKILL.md` 与 `.agents/skills/vp-e2e/references/diagnostics.md`。实现者须研读该技能的技能机制章节后再动手。

## 阶段划分

1. [注释规则扩到 Scripts 与存量清零](phase-1-script-comment-rule.md)
2. [删 runctl 的 run 子命令与 _run_full](phase-2-retire-runctl-run.md)
3. [删 sidekick_runner 与 MainAgentCoordinator](phase-3-retire-sidekick-runner.md)
4. [拆出 agent identity，删 AgentOracleProvider](phase-4-extract-agent-identity.md)
5. [删批量 campaign 启动入口](phase-5-retire-campaign-launcher.md)
6. [删授权超时分支与两行分流](phase-6-drop-authorization-timeout.md)
7. [Verdict 与账本终态类型](phase-7-verdict-and-terminal-states.md)
8. [账本锁与 ledger 工具](phase-8-ledger-lock-and-tool.md)
9. [MCP server 骨架与 session 工具](phase-9-mcp-server-and-session.md)
10. [op 工具与 L1 像素启发](phase-10-op-tool.md)
11. [模拟器分段录屏与异常抽帧](phase-11-simulator-segment-recording.md)
12. [bundle 工具](phase-12-bundle-tool.md)
13. [rubric 谓词编译器与覆盖报告](phase-13-rubric-predicate-compiler.md)
14. [逐 Operation 实现 digest](phase-14-per-operation-digest.md)
15. [已知缺陷账本](phase-15-known-defect-ledger.md)
16. [session --mode human 与时间线轮询](phase-16-human-session-mode.md)
17. [人类收据与 receipt 工具](phase-17-human-receipt.md)
18. [path 到 tier 重切](phase-18-tier-recut.md)
19. [文档同步](phase-19-doc-sync.md)

跨阶段的验证约定见 [testing.md](testing.md)。

## 全量验证

静态门：

```sh
python3 Scripts/rules/run_verification.py
```

模拟器 lane 端到端，以工具集自身走一遍。`op` 从同一组入参就地编译计划，因此不需要先单独 compile 一份 `plan.json`；`open_run` 会把编译结果与 run 目录里既有的 `plan.json` 逐字节比对。

```sh
python3 Scripts/regression/runctl.py freeze \
  --artifact-root .scratch/harness-tools \
  --simulator-target <模拟器 UDID> --device-target <真机 UDID> \
  --agent-model <模型> --output execution-input.json

python3 Scripts/regression/tools/server.py --once session \
  --mode agent --device <模拟器 UDID> --stage ensure \
  --execution-input .scratch/harness-tools/execution-input.json \
  --output-directory .scratch/<日期>-harness-tools/evidence
python3 Scripts/regression/tools/server.py --once op \
  --repository-root . \
  --execution-input .scratch/harness-tools/execution-input.json \
  --catalog-root Regression --policy Regression/policy.json \
  --reviews-root Regression/reviews --blueprint Regression/blueprint.json \
  --run-directory .scratch/harness-tools/run \
  --node <NodeID> --call <CallID> \
  --lane simulator --target <模拟器 UDID> --sidekick sidekick:one
python3 Scripts/regression/tools/server.py --once ledger \
  --action view --run-directory .scratch/harness-tools/run
python3 Scripts/regression/tools/server.py --once receipt \
  --run-directory .scratch/harness-tools/run
```

合并授权仍走既有路径：

```sh
python3 Scripts/rules/merge_authority.py generate origin/main..HEAD \
  --change-kind regression-contract \
  --evidence verification-green=.scratch/Verification/runs/<run>/summary.json \
  --evidence simulator-e2e=.scratch/harness-tools/<run> \
  --approval .scratch/merge/approval.json \
  --output .scratch/merge/run-receipt.json
```

## 落地后的实际形状

十九个阶段落地之后，与设计定稿时的差异集中在四处，都由实测或对抗审查推动：

- **判读三级的实际覆盖是可数的。** 97 份 rubric 的 199 条 criterion 里，17 条能抽出至少一个字段谓词，共 18 个谓词；其余 182 条仍由 Agent 判读并逐条列在覆盖报告里。基线走 ratchet，覆盖率只能升。这两个数最初记的是 47 与 48：编译器的字段表里有 `requireMatchedElement`，它是 `operation:accessibility.inspect@2` 的入参（`Scripts/verification/regression_operation_adapter.py:2807`，读于 `:4520`），不出现在任何一次调用的 outputs 里，48 个谓词里有 30 个因此恒为 `indeterminate`。2026-09-05 把该字段移出字段表并把基线下调到实际可读的数目——ratchet 拦的是无声的下滑，不是一次记账修正。
- **账本多了一个「重开」事实。** 人类层的进入条件要求同一节点有两次 attempt，而原状态机里一个节点只能被 claim 一次。`NODE_REOPENED` 只接受归因为 harness 的 `indeterminate`，上限两次，全部候选 lane 中断时拒绝，且回放时核对它自称的 attempt 数。
- **逐 Operation digest 按 handler 源码段算。** 35 个 Operation 合同共用同一个 `implementation.locator`，按文件算达不到「只失效用过该 Operation 的节点」。实测：改一个 handler 只改一个 digest，改共享代码改全部 35 个。这条实测最初只在类外的代码上成立：`ResidentOperationBackend` 的 80 个方法被整体剔出共享 digest，其中 45 个（2338 行）不服务任何 Operation，改动它们一个 digest 都不动。2026-09-05 起剔除范围收窄到 Catalog 点名的 35 个 handler，类内非 handler 方法的改动同样使全部 35 个 digest 失效。
- **异常包的裁切没有产出。** `matchedElement.frame` 的单位是点，截图是像素，响应里没有任何字段记录屏幕的点尺寸。按猜的比例裁切会把错的区域配上裁决文字，因此逐条说明为什么产不出。

未闭合的缺口逐条记在[阶段 15](phase-15-known-defect-ledger.md) 的「未闭合的缺口」一节，其中最重要的一条是：`verdict.signature` 与运行期实际命中的签名之间还没有绑定。

## 实施指引

- 改动任何不熟悉的子系统前，先调用 **how** 技能透彻理解其实现脉络。`Scripts/regression/core/runtime.py`、`Scripts/regression/completion.py` 与 `Scripts/verification/regression_operation_adapter.py` 三者各自超过 2000 行，任何一处的隐式约束都值得先走读。
- 存在争议的架构设计在合并上线前，调用 **interrogate** 技能执行对抗式深度审查。账本锁与已知缺陷账本两项改变运行是否允许继续，必须过这一关。
- 提交每个 commit 前，以及输出任何自然语言文本时，严格应用 **unslop** 技能。
- 本计划规模跨 19 个阶段并涉及不可逆删除，调用 **show-me-your-work** 技能记录完整的决策记录链。
- 提交 PR 后，启动 Cursor 内置的 **babysit** 技能持续看护。
