[← overview](overview.md)

# 阶段 8：账本锁与 ledger 工具

## 目标

实现护栏：某 lane 出现非 Satisfied 后，该 lane 的下一次 op 被拒绝，直到 ledger 收到裁决。同时把账本的写裁决、查状态、查续跑点三件事收成一个工具。

## 原改动清单的失效

原清单假定「记录节点终态」与「记录归因」是两次账本写入，锁在两者之间生效。当前实现把它们合成一次：

- `Scripts/regression/core/runtime.py:1565` 的 `_evaluate_and_record` 在同一次调用内追加 `ORACLE_EVALUATED`，随即对 VIOLATED 调 `_record_verdict(node, FAILED)`，对 Indeterminate 调 `interrupt_lane`；后者在 `runtime.py:1101` 写 `_record_verdict(node, INDETERMINATE)`。非 Satisfied 的聚合结束时节点已经终态。`runtime.py:1755` 的恢复路径持有同一段分支的第二份拷贝。
- `Scripts/regression/core/runview.py:1377` 拒绝落在非 `PENDING`／`LEASED` 节点上的裁决，`Scripts/regression/core/replay.py:106` 拒绝重复的 `verdict:{node}` 幂等键。每个节点只有一次裁决事件，归因无法事后补写。

锁要守的那段状态不存在。本阶段令它存在：非 Satisfied 的聚合不再关闭节点，节点停在 `LEASED`，lease 停在 `ACTIVE`，直到裁决到达。

## 方案比选

- 甲，裁决之后追加一条归因事件。runtime 关闭节点的时机不变。`runview.py:1418` 在写入终态时清空 `lane.active_lease_id` 且不标记 lane 中断，于是 `_claim_node`（`runview.py:974`）接受该 lane 上的下一个 `NODE_CLAIMED`，伪造的账本仍能 replay：护栏只在调用方记得查询锁时成立。Indeterminate 一侧相反，它经 `interrupt_lane` 关闭，lane 的 `interrupted` 不可撤销（`runview.py:1450`），写入归因也解不开锁。终态在归因之前就已固定，阶段 15 的 `classify(verdict, fields) -> NodeStatus` 无处插入，`failed(known)` 与 `deferred(human)` 都写不出来。
- 乙，新增非终态 `ADJUDICATING` 与一条 runtime 写的事件。lane 的准入读的是 `lane.active_lease_id` 与 `lane.interrupted`（`runview.py:974`），不读节点状态：新状态只有在 lease 保持 `ACTIVE` 时才拦得住下一次 claim，而那正是丙的机制。lease 一旦释放，甲的缺口原样重现。代价是在阶段 7 落地一个阶段之后修改它的终态契约。
- 丙，等待裁决即 `LEASED`。runtime 删去非 Satisfied 的两条关闭分支，节点保持 `LEASED`、lease 保持 `ACTIVE`。此后每一条通往该 lane 的路径都已经拒绝：`MainRun.claim` 在 `runtime.py:656` 抛 `runtime.lane_busy`，`_claim_node` 在 `runview.py:976` 于 replay 时拒绝同样的事件，同一 lease 上的后续调用因 `cursor == len(calls)` 而没有 `current_call`。

选丙。锁因此是一条转移规则而不是一条工具约定：在锁住的 lane 上继续跑 op 的账本无法 replay。`lane_lock_state` 解释这条拒绝，不制造它。阶段 7 的终态契约不动，`NodeStatus` 与 `EventType` 都不新增成员。

`LEASED` 在本阶段之后承载两种情形：工作进行中，与工作结束等待裁决。判别项是同一个 lease 的 `operations_complete`、`evidence_accepted`，以及由 `success` 与已记录的 obligation 结果重算出的聚合非 Satisfied。聚合必须参与判别，理由见下方准入表一节。

## 改动清单

本阶段落两个 commit。前者改状态机，后者加工具。

### 状态机

- `Scripts/regression/core/runtime.py`。`_evaluate_and_record`（:1565）只保留 SATISFIED 分支的 `_record_verdict(node.id, PASSED, lease.lease_id)`；`_recover_uncertain_invocations`（:1755）同样只保留该分支，`bootstrap_and_recover` 每次 `open_run` 都会调它，绿色节点在「最后一条 `ORACLE_EVALUATED` 与 `PASSED` 之间崩溃」后仍自愈。`interrupt_lane`（:1101）对等待裁决的节点不再写 `INDETERMINATE`，lane 照常记录中断，节点照常欠裁决；这里是约二十个中断调用点唯一的节点关闭写入。`finalize`（:1195）在清扫 `LEASED` 之前对等待裁决的节点抛错并列出 NodeID。`accept_evidence`（:953）的终态提前返回把字面元组换成 `TERMINAL_NODE_STATUSES`，该元组早于阶段 7，漏掉了三个终态。`_node_open_payload`（:2016）给 scenarioAttempt 节点补 `success` 字段，复用 `plan.py:1269` 的 `_success_payload`。
- `Scripts/regression/core/runview.py`。`NodeView` 增 `success: SuccessExpression | None`，`_open_nodes` 用 `expression.parse_success_expression` 解析，scenarioAttempt 必须有、bothJoin 必须没有。`_record_verdict`（:1368）定义等待裁决的判别项，并在该状态下由 `success` 与 `lease.oracle_evaluations` 重算 `evaluate_success`，核对声明的终态。
- `Scripts/regression/core/ledger.py`。`LedgerWriter` 增一个必填构造参数 `fold`，`append` 在 `write`／`flush`／`fsync` 之前用候选事件列表调它，抛错即不落盘。`open_run` 传 `build_run_view`，阶段 8 的 ledger 工具同样传它。`fold` 由调用方注入而不写死在 `append` 里：`LedgerWriter` 是哈希链与文件格式层，`build_run_view` 是语义层，写死会让 `Scripts/rules/test_regression_core_ledger.py` 的十二处合成 payload——篡改、截断、序号跳变、幂等冲突——全部先撞上状态机，格式层从此无法单独测试。参数必填，遗漏在 diff 里是一处显式改动而不是一次沉默。`MainRun.view`（`runtime.py:599`）本就在每次读取时重跑整份 fold，本改动是常数倍开销，不改变量级。
- `Scripts/rules/test_regression_core_runtime.py`。VIOLATED 路径的 `receipt.node_status` 由 `FAILED` 改为 `LEASED`；Indeterminate 路径不再中断 lane；补：`interrupt_lane` 不能把等待裁决的节点洗成 `INDETERMINATE`、`finalize` 拒绝等待裁决的节点、VIOLATED lease 上写 `passed` 被拒、不带裁决字段的 `failed` 被拒、越界的 `firstDeviantFrame` 被拒且 `ledger.jsonl` 字节数不变。

`success` 表达式进 `RUN_OPENED` 是重算的前提。`plan.py:1269` 的 `_success_payload` 产出的形状正是 `expression.py:59` 的 `parse_success_expression` 接受的形状，字段可往返。替代做法是拿 `runview.py:95` 的 `aggregate_oracle_results` 顶替 `evaluate_success`，那在真实数据上就是错的：`AllOf` 对 `{VIOLATED, INDETERMINATE}` 给 VIOLATED（`expression.py:389`），原始聚合给 INDETERMINATE（`runview.py:96`），Catalog 现有的 52 个 Scenario 全部用 `all`。

裁决的准入表由聚合结果给出，不由归因给出。归因记录的是「为什么」，终态记录的是「Oracle 看到了什么」：

```text
SATISFIED       只许 passed，且不得携带裁决字段
VIOLATED        只许 failed 或 failed(known)；failed(known) 必须带 signature
INDETERMINATE   只许 indeterminate
结果尚未定       只许 indeterminate，且不得携带裁决字段
```

聚合在评估集不完整时照样求值，缺失的 obligation 以 `INDETERMINATE` 代入：`AllOf` 只要有一项已记录为 VIOLATED 就是 VIOLATED（`expression.py:389`），`AnyOf` 要全部 VIOLATED 才是 VIOLATED，`AtLeast` 把代入项计入 indeterminate 因而只会更难判负，`Not` 对 INDETERMINATE 仍是 INDETERMINATE。代入只会让判定更保守，得出的 SATISFIED 或 VIOLATED 对任何一种补全都成立。「结果尚未定」专指代入之后仍为 INDETERMINATE 且评估集不完整的情形。

这条区分是护栏的一部分，不是精度问题。若以「评估集是否完整」作判别项，一条已记录 VIOLATED 的半评估 lease 会被判为无结果，`indeterminate` 裁决因此获准写入，而该裁决清空 `lane.active_lease_id` 且不标记 lane 中断（`runview.py:1508`），lane 就在没有任何归因的情况下重新开放。

`deferred(human)` 不在表内。它的入口条件是同一节点连续两次 attempt 均为 harness 超时类，判定函数 `deferrable(view, node)` 由阶段 16 提供；在那之前把它放进准入表等于开一个无人把守的出口——`DEFERRED_HUMAN` 不属于 `PRODUCT_NODE_STATUSES`，会绕过 `runview.py:1400` 的证据义务并释放 lane。阶段 16 与 `deferrable` 一并放行。「产品慢是 Violated，写 `failed`，不可推迟」由此在 replay 层成立，不靠调用方自觉。

### 工具

- 新增 `Scripts/regression/tools/ledger_lock.py`。`lane_lock_state(view, lane) -> LaneLock` 按序判五件事：整轮已关闭、该 lane 持有欠裁决的节点、该 lane 已中断、lease 的评估结果尚未定、lease 仍在跑操作；五者皆不成立才是开放。`locked` 的含义是「这条 lane 接不了新的 claim」，不是「欠裁决」，因此中断与整轮关闭同样落在 `locked` 内——`MainRun.claim` 拒绝它们的方式与拒绝忙碌 lane 相同，工具不该把已关闭的 run 报成开放。中断优先于 lease 扫描：崩在 `LANE_INTERRUPTED` 与其 `INDETERMINATE` 裁决之间的节点仍是 `LEASED`，但那条 lane 上不会再有操作。结果尚未定时给一个独立的 reason：那是崩在两条 `ORACLE_EVALUATED` 之间且已记录的部分尚不足以定论的停滞，重开 run 即结清，不欠裁决；已记录部分足以定论 VIOLATED 的半评估 lease 不属于此列，它欠裁决。`admit_verdict(view, verdict, status, bundle_frame_count) -> None` 拒绝越界的 `first_deviant_frame`、空的 `region_observation`、缺 signature 的 `failed(known)`、与聚合结果不符的终态、以及不处于等待裁决的节点。每一条在 `runview._record_verdict` 里都有对应规则，本层只负责先给出可读的拒绝理由。
- 新增 `Scripts/regression/tools/ledger_tool.py`。`write` 接 `Verdict`、终态与 `bundle_frame_count`，过 `admit_verdict` 后交 `LedgerWriter`；`view` 返回 `replay(run_directory)` 的投影加逐 lane 的 `LaneLock`；`resume` 返回依赖已满足、lane 未锁、状态非终态的节点清单，并单列欠裁决的节点，否则清单为空时读不出原因。
- `Scripts/regression/core/runview.py`。`_settle_derivable_nodes` 的推导规则移出 `MainRun`，成为只读 RunView 的 `derivable_verdict` 与 `settled_node_statuses`，`runtime` 与 `resume` 共用一份。`claim` 在挑选候选之前先跑一次结算（`runtime.py:653`）；若 `resume` 另写一套就绪判据，崩在 join 节点 `PASSED` 裁决之前的账本会让两者答案不同：`resume` 漏报后继节点，下一次 `claim` 却立刻把它派出去。
- 新增 `Scripts/rules/test_regression_ledger_lock.py`。覆盖：非 Satisfied 后同 lane 的 claim 被 `runtime.lane_busy` 拒、裁决写入后解锁并可再 claim、帧序号越界被拒、绿色步骤不锁、两条 lane 的锁互不影响、中断与整轮关闭都报为锁住、结果尚未定的 lease 不欠裁决、`resume` 扣下锁住 lane 上的同侪节点并在解锁后交还、`resume` 与下一次 claim 对 join 后继节点的答案一致、伪造一条在锁住的 lane 上 `NODE_CLAIMED` 的账本行被 replay 拒绝。

三个新文件都不得含注释。

## 数据结构与形态

```python
LaneLock(lane: BoundLane, locked: bool, pending_node: NodeID | None, reason: str)

lane_lock_state(view: RunView, lane: BoundLane) -> LaneLock
admit_verdict(
    view: RunView,
    verdict: Verdict,
    status: NodeStatus,
    bundle_frame_count: int,
) -> None
```

ledger 工具的对外形状：

```text
ledger write  --run-directory --status --verdict-json --bundle-frame-count
                                                      -> 新的账本视图
ledger view   --run-directory [--lane]                -> {nodes, lanes, locks}
ledger resume --run-directory                         -> {ready, awaitingVerdict}
```

`--verdict-json` 自带 `node` 字段，命令面不再单列 `--node`。`bundle_frame_count` 随裁决落进 payload，`0 <= firstDeviantFrame < bundleFrameCount` 因此在 replay 时可复核。阶段 12 产出真实拼图帧数后只换来源，不换校验位置。

## 2026-09-05 对抗审查后的收紧

[interrogate](interrogate-2026-09-05.md) 的四位审查者在同一个根因上一致：回放层比工具层宽。`admit_verdict` 拒绝的裁决，直接追加成账本行就能回放通过——与本阶段「锁是转移规则而不是工具约定」的原则相反。收紧后的形状：

- **准入表只有一张。** `admissible_verdicts(settled, ended_on_the_harness)` 长在 `runview.py`，回放的 `_record_verdict` 与工具的 `admit_verdict` 都查它。表按「节点是否持有 lease」分两半：无 lease 的节点只接受 `indeterminate`（`finalize` 写的），或与 `derivable_verdict` 逐项相等的派生结论（join 的 `passed`、失败祖先之后的 `blockedBy`）；有 lease 的节点按聚合结果查上文的四行表，聚合未定且终局调用以仪器故障收场时只许 `indeterminate` 与 `deferred(human)`。原实现把 `deferrable_from` 与「结果尚未定只许 indeterminate」两条都写在 `LEASED` 分支里，`PENDING` 节点因此可以被写成 `deferred(human)`，前驱全部 `PENDING` 的 join 可以被写成 `passed`。
- **`blockedBy` 的祖先由 run 派生。** 原实现对 `failureAncestors` 只做标识符解析，一行指向不存在节点的 `blockedBy` 能关掉任意节点、解开 lane 锁并让整轮收口为 `passed`。现在它必须等于 `derivable_verdict` 算出的集合。
- **`bundleFrameCount` 在回放层有上界。** 帧数原本只在 `ledger_tool.write` 里从 run 派生，进了 payload 之后回放只校验 `firstDeviantFrame` 落在它之内，两者出自同一份自述。`montage_frame_bound(lease)` 数该 lease 最后两次完成调用里带截图键的条数——`frames_of` 的结构常量——声明值不得超过它。
- **同一条规则的两份副本合并。** `runtime._evaluate_and_record` 与 `_recover_uncertain_invocations` 各自手写「聚合是否 SATISFIED」，在 `AnyOf` 下与 `settled_oracle_result` 不等价；两处改调后者。`runtime._record_verdict` 的幂等键补上 attempt，与 `ledger_tool` 同一格式；`finalize` 的清扫按节点取 `current_lease`，不再按 lease 排序取到已停掉的第一次 attempt。`_reopen_node` 用 `_integer` 核对 `attemptsBefore`（`True` 不再等于 `1`），并清掉旧 lane。
- **回放层的每条拒绝都有直接追加账本行的自测。** `Scripts/rules/test_regression_replay_admission.py` 对上面每一条各追加一行伪造事件；重开的五种拒绝理由此前只经 `ledger_tool.reopen` 测过，变异掉 `reopen_refusal` 四个套件全绿，现在各有孪生用例。

## 阶段验证方案

状态机 commit：

```sh
python3 Scripts/rules/test_regression_core_runtime.py
python3 Scripts/rules/test_regression_verdict.py
python3 Scripts/rules/verify_regression_core_layering.py
python3 Scripts/rules/run_verification.py --quick
```

工具 commit：

```sh
python3 Scripts/rules/test_regression_ledger_lock.py
python3 Scripts/rules/run_verification.py --quick
```

运行时：无。`lane_lock_state` 与 `admit_verdict` 的输入是 RunView，不触及设备。锁在真实设备上的效果由阶段 10 的 op 工具证明，那时才有会被拒绝的调用。
