[← overview](overview.md)

# 阶段 2：删 runctl 的 run 子命令与 _run_full

## 目标

`Scripts/regression/runctl.py` 只保留 `prepare-build`、`freeze`、`compile`、`status` 四个子命令。「跑完一组」的入口消失，`sidekick_runner` 与 `oracle_agent` 失去唯一的生产调用方，供后两个阶段删除。

先删这一层，因为它是依赖树的根：`runctl.py:53` 导入 `open_main_agent`，`runctl.py:50` 导入 `AgentOracleProvider`。反序删除会在中间状态留下无法导入的模块。

## 改动清单

- `Scripts/regression/runctl.py`。删 `_run_full`（:386-456）、`execute_lanes`（:245-324）、`LaneExecutionError`（:61）、`LaneExecutionResult`（:68）、`_assert_ignored_runtime_path`（:373）与 `_write_once` 的 run 分支调用点；删 `_parser()` 中的 `run_parser`（:535-537）；删 `_execute()` 末尾对 `_run_full` 的转发（:605-613），改为对未知 operation 的显式拒绝。删对应的 import：`AgentOracleProvider`（:50）、`open_main_agent`（:53）、`RegressionOracleAdapter`（:54）、`SidekickID`（:28）、`RunOutcome`（:41）、`threading`（:12）。保留 `_view_payload`、`compile_execution_plan`、`load_current_reviewed_catalog`、`load_blueprint_fact_values`、`derive_reviewed_facts`，`Scripts/regression/completion.py:46` 导入前三个，`Scripts/rules/test_regression_execution_identity.py:39` 导入 `_prepared_build_payload`。
- `Scripts/rules/test_regression_runctl.py`。删三个绑定 run 路径的用例：`test_run_exports_and_restores_the_frozen_input_locator`（:410）、`test_lane_execution_overlaps_simulator_and_device`（:599）、`test_lane_failure_does_not_cancel_the_other_lane`（:609），以及 :39 与 :42 的 `_run_full`、`execute_lanes` 导入。保留 `prepare-build`、`freeze`、`compile` 的参数面用例。
- `Scripts/rules/verify_bootstrap_freeze.py`。该检查读 `runctl.py` 源码文本断言 `--bootstrap` 选项与它到 `freeze_execution_input` 的转发（:57-61）。两处都在 `freeze` 分支，不受本阶段影响；跑一遍确认。

`Scripts/verification/reachability_matrix.py:209` 的拒绝文案引用 `python3 Scripts/regression/runctl.py --help`，`compile` 与 `status` 仍在，文案继续成立，不改。

## 数据结构与形态

删除后 `runctl.py` 的对外形状：

```text
prepare-build --artifact-root                     -> 逐 lane 构建溯源
freeze --artifact-root --simulator-target ...     -> ExecutionInput（BuildIdentity + EvidenceEnvironmentIdentity）
compile --execution-input --reviews-root --output -> CompiledRunPlan 字节
status --run-directory                            -> replay(RunDirectory) 的 RunView
```

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_runctl.py
python3 Scripts/rules/verify_bootstrap_freeze.py
python3 Scripts/rules/test_bootstrap_freeze.py
```

运行时：

```sh
python3 Scripts/regression/runctl.py compile \
  --reviews-root Regression/reviews \
  --execution-input .scratch/harness-tools/execution-input.json \
  --output .scratch/harness-tools/plan.json
```

这条命令跑通证明编译层不依赖被删的流程层。它不需要设备。
