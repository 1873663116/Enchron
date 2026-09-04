[← overview](overview.md)

# 阶段 7：Verdict 与账本终态类型

## 目标

定义工具集共用的两个核心类型：一次 op 的裁决 `Verdict`，与一个节点写进账本的终态 `LedgerEntry`。终态枚举从当前的六个值改为设计要求的六个终态加两个非终态。这两个类型是后面八个阶段的共同底座，先落地。

## 改动清单

- `Scripts/regression/core/runview.py`。`NodeStatus`（:46）改为：非终态 `PENDING`、`LEASED`；终态 `PASSED`、`FAILED`、`FAILED_KNOWN`（`failed(known)`）、`BLOCKED_BY`（`blockedBy`）、`DEFERRED_HUMAN`（`deferred(human)`）、`INDETERMINATE`。原 `INTERRUPTED` 重命名为 `INDETERMINATE`：`Regression/README.md` 已写明 Oracle 的 `Indeterminate` 只能重试或产生 `InterruptedRunReceipt`，节点层的 interrupted 一直是 indeterminate 的别名。`RunOutcome.INTERRUPTED`（:64）不动，它描述整轮运行被中断，不是节点判读。流程层从未产出过一次完整运行，没有既有 run 目录的 replay 需要兼容。
- 新增 `Scripts/regression/tools/verdict.py`。定义 `Verdict` 与 `Attribution`。`Verdict` 冻结不可变，字段校验在 `__post_init__` 完成：`firstDeviantFrame` 为非负整数或 `None`，`attribution` 取自闭合枚举，`signature` 为已登记的签名 id 或 `None`。序号是否越界由阶段 8 的账本锁在拿到拼图帧数后判定，本类型只保证类型与非负。
- 新增 `Scripts/rules/test_regression_verdict.py`。覆盖：终态枚举的字符串值、`Verdict` 的字段校验、非法 attribution 被拒。

两个新文件都不得含注释。

## 数据结构与形态

```python
Attribution = Enum("product" | "harness" | "spec")

Verdict(
    node: NodeID,
    first_deviant_frame: int | None,
    region_observation: str,
    attribution: Attribution,
    signature: SignatureID | None,
)

NodeStatus = pending | leased
           | passed | failed | failed(known) | blockedBy | deferred(human) | indeterminate
```

`LedgerEntry` 是 `NodeStatus` 的终态取值加上写入它的 `Verdict`，落盘形状由 `Scripts/regression/core/events.py` 的既有事件编码承载，本阶段不新增事件类型。

终态集合在 `runview.py` 落为三个具名常量，取代原先散在 `_record_verdict` 各分支里的字面元组：

```text
TERMINAL_NODE_STATUSES         六个终态，判定「这条裁决是否终态」
PRODUCT_NODE_STATUSES          passed | failed | failed(known)，判定「是否需要完整操作与已评据」
PRODUCT_FAILURE_NODE_STATUSES  failed | failed(known)，判定「join 节点是否越权制造产品失败」
```

`failed(known)` 属于产品裁决，与 `failed` 承担同一套证据义务；差别只在阶段 15 的已知缺陷账本是否放行收据，不在证据要求上。`deferred(human)` 与 `indeterminate` 不属于产品裁决：前者的入口条件是连续两次 harness 超时，后者没有可评的 Oracle 结果，都不该被要求提供 Oracle 评估。

两处留给后续阶段收口：

- `Verdict.signature` 本阶段只校验 `signature:<colon-path>` 格式，任何格式合法但未登记的 id 都会通过。阶段 12 建立签名表后，该分支要改为查表，而不只是新增表。
- `runtime.py:1215` 由节点状态推 `RunOutcome` 的分支只认 `INDETERMINATE`、`FAILED` 与 `PASSED|BLOCKED_BY`，`FAILED_KNOWN` 与 `DEFERRED_HUMAN` 落到 `else` 的 `RunOutcome.INTERRUPTED`。这是保守取值，不会把未处理状态误判为通过；阶段 15 与阶段 16 引入生产者时一并收口。

阶段 8 不改动本阶段的终态契约：`pending` 与 `leased` 仍是仅有的两个非终态，`NodeStatus` 与 `EventType` 都不新增成员。`leased` 在阶段 8 之后承载两种情形——工作进行中，与工作结束等待裁决——判别项是同一个 lease 的 `operations_complete` 与 `evidence_accepted`。

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_verdict.py
python3 Scripts/rules/test_regression_core_runtime.py
python3 Scripts/rules/verify_regression_core_layering.py
```

`test_regression_core_runtime.py` 用假 lane 覆盖状态机，是终态重命名是否漏改的判据。

运行时：无。本阶段只定义类型，没有工具入口可跑。
