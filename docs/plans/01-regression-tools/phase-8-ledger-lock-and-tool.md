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

`LEASED` 在本阶段之后承载两种情形：工作进行中，与工作结束等待裁决。判别项是同一个 lease 的 `operations_complete` 与 `evidence_accepted`，两者皆真即等待裁决。判别项不含聚合结果：`runtime.py:1566` 自行关闭每个 SATISFIED 节点，仍停在该状态的节点按构造即非 Satisfied。

## 改动清单

本阶段落两个 commit。前者改状态机，后者加工具。

### 状态机

- `Scripts/regression/core/runtime.py`。`_evaluate_and_record`（:1565）只保留 SATISFIED 分支的 `_record_verdict(node.id, PASSED, lease.lease_id)`；`_recover_uncertain_invocations`（:1755）同样只保留该分支，`bootstrap_and_recover` 每次 `open_run` 都会调它，绿色节点在「最后一条 `ORACLE_EVALUATED` 与 `PASSED` 之间崩溃」后仍自愈。`interrupt_lane`（:1101）对等待裁决的节点不再写 `INDETERMINATE`，lane 照常记录中断，节点照常欠裁决；这里是约二十个中断调用点唯一的节点关闭写入。`finalize`（:1195）在清扫 `LEASED` 之前对等待裁决的节点抛错并列出 NodeID。`accept_evidence`（:953）的终态提前返回把字面元组换成 `TERMINAL_NODE_STATUSES`，该元组早于阶段 7，漏掉了三个终态。`_node_open_payload`（:2016）给 scenarioAttempt 节点补 `success` 字段，复用 `plan.py:1269` 的 `_success_payload`。
- `Scripts/regression/core/runview.py`。`NodeView` 增 `success: SuccessExpression | None`，`_open_nodes` 用 `expression.parse_success_expression` 解析，scenarioAttempt 必须有、bothJoin 必须没有。`_record_verdict`（:1368）定义等待裁决的判别项，并在该状态下由 `success` 与 `lease.oracle_evaluations` 重算 `evaluate_success`，核对声明的终态。
- `Scripts/regression/core/ledger.py`。`append`（:115）在 `write`／`flush`／`fsync` 之前，用候选事件跑一次 `build_run_view(self._events + (event,))`，通过才落盘。`MainRun.view`（`runtime.py:599`）本就在每次读取时重跑整份 fold，本改动是常数倍开销，不改变量级。`verify_regression_core_layering.py` 的 `ledger` 条目增加 `runview`，该依赖此前经 `replay` 间接成立。
- `Scripts/rules/test_regression_core_runtime.py`。VIOLATED 路径的 `receipt.node_status` 由 `FAILED` 改为 `LEASED`；Indeterminate 路径不再中断 lane；补：`interrupt_lane` 不能把等待裁决的节点洗成 `INDETERMINATE`、`finalize` 拒绝等待裁决的节点、VIOLATED lease 上写 `passed` 被拒、不带裁决字段的 `failed` 被拒、越界的 `firstDeviantFrame` 被拒且 `ledger.jsonl` 字节数不变。

`success` 表达式进 `RUN_OPENED` 是重算的前提。`plan.py:1269` 的 `_success_payload` 产出的形状正是 `expression.py:59` 的 `parse_success_expression` 接受的形状，字段可往返。替代做法是拿 `runview.py:95` 的 `aggregate_oracle_results` 顶替 `evaluate_success`，那在真实数据上就是错的：`AllOf` 对 `{VIOLATED, INDETERMINATE}` 给 VIOLATED（`expression.py:389`），原始聚合给 INDETERMINATE（`runview.py:96`），Catalog 现有的 52 个 Scenario 全部用 `all`。

裁决的准入表由聚合结果给出，不由归因给出。归因记录的是「为什么」，终态记录的是「Oracle 看到了什么」：

```text
SATISFIED       只许 passed，且不得携带裁决字段
VIOLATED        只许 failed 或 failed(known)；failed(known) 必须带 signature
INDETERMINATE   只许 indeterminate
评估集不完整      只许 indeterminate
```

`deferred(human)` 不在表内。它的入口条件是同一节点连续两次 attempt 均为 harness 超时类，判定函数 `deferrable(view, node)` 由阶段 16 提供；在那之前把它放进准入表等于开一个无人把守的出口——`DEFERRED_HUMAN` 不属于 `PRODUCT_NODE_STATUSES`，会绕过 `runview.py:1400` 的证据义务并释放 lane。阶段 16 与 `deferrable` 一并放行。「产品慢是 Violated，写 `failed`，不可推迟」由此在 replay 层成立，不靠调用方自觉。

### 工具

- 新增 `Scripts/regression/tools/ledger_lock.py`。`lane_lock_state(view, lane) -> LaneLock` 判该 lane 的 `active_lease_id` 非空、其节点 `LEASED`、lease 的 `operations_complete` 与 `evidence_accepted` 皆真。评估集不完整时给一个独立的 reason：那是崩在两条 `ORACLE_EVALUATED` 之间的停滞，重投同一 envelope 即可恢复，不欠裁决。`admit_verdict(view, verdict, status, bundle_frame_count) -> None` 拒绝越界的 `first_deviant_frame`、空的 `region_observation`、缺 signature 的 `failed(known)`、以及不处于等待裁决的节点。每一条在 `runview._record_verdict` 里都有对应规则，本层只负责先给出可读的拒绝理由。
- 新增 `Scripts/regression/tools/ledger_tool.py`。`write` 接 `Verdict`、终态与 `bundle_frame_count`，过 `admit_verdict` 后交 `LedgerWriter`；`view` 返回 `replay(run_directory)` 的投影加逐 lane 的 `LaneLock`；`resume` 返回依赖已满足、lane 未锁、状态非终态的节点清单，并单列欠裁决的节点，否则清单为空时读不出原因。
- 新增 `Scripts/rules/test_regression_ledger_lock.py`。覆盖：非 Satisfied 后同 lane 的 claim 被 `runtime.lane_busy` 拒、裁决写入后解锁并可再 claim、帧序号越界被拒、绿色步骤不锁、两条 lane 的锁互不影响、中断路径下节点仍欠裁决、伪造一条在锁住的 lane 上 `NODE_CLAIMED` 的账本行被 replay 拒绝。

四个新文件都不得含注释。

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
ledger write  --run-directory --node --status --verdict-json --bundle-frame-count
                                                      -> 新的账本视图
ledger view   --run-directory [--lane]                -> {nodes, lanes, locks}
ledger resume --run-directory                         -> {ready, awaitingVerdict}
```

`bundle_frame_count` 随裁决落进 payload，`0 <= firstDeviantFrame < bundleFrameCount` 因此在 replay 时可复核。阶段 12 产出真实拼图帧数后只换来源，不换校验位置。

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
