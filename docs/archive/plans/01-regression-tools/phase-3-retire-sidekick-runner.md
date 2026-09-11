[← overview](overview.md)

# 阶段 3：删 sidekick_runner 与 MainAgentCoordinator

## 目标

删掉 Main 与 Sidekick 的调度层。lease 的分配、Sidekick 的领取与归还、双 lane 的并发推进全部消失。`Scripts/regression/core/runtime.py` 中 `MainRun` 的 claim、Operation 授权、证据接受、lane 中断与 finalize 全部保留，由后续的 MCP 工具直接调用。

## 改动清单

- 删 `Scripts/regression/sidekick_runner.py`（1205 行）。它导出 `open_main_agent` 与 `MainAgentCoordinator`。阶段 2 之后唯一的导入方是它自己的自测。
- 删 `Scripts/rules/test_regression_sidekick_runner.py`（1657 行）。
- `Config/harness_primitives_allowlist.json`。该文件登记允许直接驱动设备的脚本。`sidekick_runner.py` 不在其中，无需改动；跑一遍 `Scripts/rules/harness_primitives_gate.py` 确认。

删除之前先跑一次全仓库确认没有别的导入方：

```sh
grep -rn "sidekick_runner\|MainAgentCoordinator\|open_main_agent" \
  --include="*.py" --include="*.md" --include="*.json" . \
  | grep -v "^./.git/" | grep -v "^./Regression/reviews/"
```

`Regression/reviews/` 下的 assessment 与 report 是内容寻址的历史审查记录，绑定当时的 packet digest，不随源码改动重写。`Regression/README.md` 中 Main 与 Sidekick 的职责描述在阶段 19 统一改。

## 数据结构与形态

删除的类型：

```python
MainAgentCoordinator(plan, run_root, build_identity, evidence_environment, lane_targets, evaluator)
  .run_sidekick(lane, target, sidekick_id) -> LeaseReceipt
  .lane_targets: Mapping[BoundLane, str]
  .finalize() -> RunView
open_main_agent(...) -> ContextManager[MainAgentCoordinator]
```

保留的类型（`Scripts/regression/core/runtime.py`）：`MainRun`，以及 `Scripts/regression/core/replay.py` 的 `replay(RunDirectory) -> RunView`。

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_core_runtime.py
python3 Scripts/rules/verify_regression_core_layering.py
python3 Scripts/rules/verify_scripts_inventory.py
```

`test_regression_core_runtime.py`（1525 行）用假 lane 证明状态机，不需要设备，是本阶段「调度层删了但状态机没坏」的直接判据。

运行时：无。本阶段只删代码，没有新的设备侧行为可证。
