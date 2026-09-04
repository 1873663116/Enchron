[← overview](overview.md)

# 阶段 15：已知缺陷账本

## 目标

Scenario 层的已知缺陷账本，终态 `failed(known)` 不阻塞收据。已知缺陷与普通失败在账本上是两个不同的终态，不是同一个终态加一条豁免注释。

## 前置阻塞：账本里没有第二次 attempt

`_claim_node` 要求节点处于 `PENDING`（`Scripts/regression/core/runview.py:1131`），而 `runtime.py` 里没有任何路径把节点写回 `PENDING`：状态只会向终态推进。因此一次 run 内一个节点只能被 claim 一次，本阶段与阶段 16 所依赖的「同一节点连续两次 attempt」在当前状态机下无法出现。这一项在阶段 12 实现 `bundle --attempt` 时暴露（见[阶段 12](phase-12-bundle-tool.md) 的偏离一节）。

### 选定：裁决之后由账本显式重开节点

- **甲，重开写进账本。** 新增事件 `NODE_REOPENED`。它只接受一种前置状态：节点为 `INDETERMINATE`，且它的裁决归因为 `harness`。重开把节点写回 `PENDING`，上一次的 lease 保持终态不变，新一次 claim 起一个新的 lease。attempt 因此是该节点 lease 的序号，可从账本读出，`bundle --attempt` 与 `deferrable` 都有据可依。上限两次：第三次重开被拒，节点只能走 `deferred(human)` 或 `failed`。
- **乙，attempt 跨 run。** `deferrable` 要读别的 run 目录才能数出两次 attempt，收据层也要跨 run 聚合。它把一个本可以留在单个 append-only 账本内的事实拆到多个文件之间，且没有任何机制保证那些 run 属于同一份计划。

选甲。重开是一个独立的事实，不是裁决的一种；把它写成事件而不是复用裁决事件，使「这个节点被重开过几次」可以从事件流直接数出来，也让转移规则留在 `_record_verdict` 旁边的同一张表里。归因限定为 `harness` 是这条出口的护栏：产品失败与 spec 失败不重试，它们的终态就是结论。

本阶段与阶段 16 合并前须走 **interrogate**：它改变「什么情况下允许继续跑」，与阶段 8 的账本锁属于同一类判断。

## 改动清单

- 新增 `Config/regression/known_defects.json`。逐条：Scenario ID、缺陷描述、命中判据（签名 id 或字段谓词）、录入日期、失效条件。失效条件是这条记录何时必须被重新审视，留空即拒绝录入。
- 新增 `Scripts/regression/tools/known_defects.py`。一个函数 `classify(verdict, fields) -> NodeStatus`。命中账本中某条记录的判据时返回 `FAILED_KNOWN`，否则返回 `FAILED`。命中判定用签名 id 或阶段 13 的 `FieldPredicate`，不用自由文本匹配。
- `Scripts/regression/tools/ledger_tool.py`。`write` 动作在写入 `FAILED` 之前先过 `classify`。
- 新增 `Scripts/rules/test_regression_known_defects.py`。覆盖：命中记录写入 `failed(known)`、未命中写入 `failed`、缺 `失效条件` 的记录被拒、`failed(known)` 不进入 lane 锁的待裁决集合、`failed(known)` 不阻塞收据。

新增的 Python 文件不得含注释。

## 数据结构与形态

```python
KnownDefect(
    scenario: ScenarioID,
    description: str,
    match: SignatureID | FieldPredicate,
    recorded: date,
    expires_when: str,
)

classify(verdict: Verdict, fields: Mapping[str, Any]) -> NodeStatus
```

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_known_defects.py
python3 Scripts/rules/test_regression_ledger_lock.py
```

运行时（模拟器 lane）：

```sh
python3 Scripts/regression/tools/server.py --once op \
  --plan .scratch/harness-tools/plan.json \
  --run-directory .scratch/harness-tools/run \
  --node <已录入已知缺陷的 NodeID> --call <CallID>

python3 Scripts/regression/tools/server.py --once ledger \
  --run-directory .scratch/harness-tools/run --view
```

对一个已录入的 Scenario 跑一次 op，账本视图中该节点为 `failed(known)`，且它所在 lane 的 `LaneLock.locked` 为假。这一对返回值证明已知缺陷既被记录也不挡路。
