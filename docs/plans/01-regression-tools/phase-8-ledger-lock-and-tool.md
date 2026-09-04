[← overview](overview.md)

# 阶段 8：账本锁与 ledger 工具

## 目标

实现护栏：某 lane 出现非 Satisfied 后，该 lane 的下一次 op 被拒绝，直到 ledger 收到裁决。同时把账本的写裁决、查状态、查续跑点三件事收成一个工具。

## 改动清单

- 新增 `Scripts/regression/tools/ledger_lock.py`。两个函数。`lane_lock_state(view: RunView, lane: BoundLane) -> LaneLock` 从 `replay` 的 RunView 判定该 lane 是否被锁：最近一个终态为非 `passed` 的节点若还没有配套裁决，lane 锁住，`LaneLock` 携带待裁决的 NodeID。`admit_verdict(view, verdict, bundle_frame_count) -> None` 校验裁决：`first_deviant_frame` 超出拼图帧数即拒绝，`region_observation` 为空即拒绝，`attribution` 与 `signature` 必须同时给出或同时缺省。绿色步骤不设锁，`passed` 终态不进入锁判定。
- 新增 `Scripts/regression/tools/ledger_tool.py`。三个动作：`write` 接受 `Verdict` 并经 `admit_verdict` 校验后交给 `Scripts/regression/core/ledger.py` 的 `LedgerWriter`；`view` 返回 `replay(run_directory)` 的 RunView 投影加上逐 lane 的 `LaneLock`；`resume` 返回续跑点，即依赖已满足、lane 未锁、状态非终态的节点清单。
- 新增 `Scripts/rules/test_regression_ledger_lock.py`。覆盖：非 Satisfied 后下一次 op 被拒、裁决写入后解锁、帧序号越界被拒、绿色步骤不锁、两条 lane 的锁互不影响。

三个新文件都不得含注释。

## 数据结构与形态

```python
LaneLock(lane: BoundLane, locked: bool, pending_node: NodeID | None, reason: str)

lane_lock_state(view: RunView, lane: BoundLane) -> LaneLock
admit_verdict(view: RunView, verdict: Verdict, bundle_frame_count: int) -> None
```

ledger 工具的对外形状：

```text
ledger write  --run-directory --node --verdict-json   -> 新的账本视图
ledger view   --run-directory [--lane]                -> {nodes, lanes, locks}
ledger resume --run-directory                         -> 可继续的 NodeID 清单
```

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_ledger_lock.py
python3 Scripts/rules/test_regression_core_runtime.py
```

运行时：无。本阶段的两个函数都是纯决策逻辑，输入是 RunView，不触及设备。锁在真实设备上的效果由阶段 10 的 op 工具证明，那时才有会被拒绝的调用。
