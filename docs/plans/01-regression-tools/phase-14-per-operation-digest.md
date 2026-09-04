[← overview](overview.md)

# 阶段 14：逐 Operation 实现 digest

## 目标

`EvidenceEnvironmentIdentity` 的全局 `deterministic_runtime_digest` 改为逐 Operation 实现 digest。一次 harness 修复只失效用过该 Operation 的节点，不再让全部既有证据一起作废。

## 改动清单

- `Scripts/regression/core/plan.py`。`EvidenceEnvironmentIdentity`（:318）的 `deterministic_runtime_digest: Digest`（:319）改为 `operation_digests: Mapping[OperationID, Digest]`。`__post_init__` 校验：映射非空、键为合法 OperationID、值为合法 Digest。`_evidence_environment_payload` 中的 `"deterministicRuntimeDigest"` 键（:1200）改为按 OperationID 排序的映射，使 `identity_digest` 保持规范化。`AgentEnvironment`（:296）不动。
- `Scripts/regression/execution_identity.py`。冻结执行输入时，逐 Operation 计算实现 digest：实现 locator 的源码字节加上 Operation 合同 digest。当前的全局 runtime digest 计算点改为对 Catalog 中每个 Operation 各算一次。
- `Scripts/regression/core/runtime.py`。证据接受时的身份比对（:1632 附近的 `runtime.oracle_agent_environment_mismatch` 一族）改为逐 Operation 比对：只有该节点实际用过的 Operation 的 digest 变了，它的证据才失效。
- `Scripts/rules/test_regression_execution_identity.py` 与 `Scripts/rules/test_regression_core_runtime.py`。补用例：改一个 Operation 的实现只失效用过它的节点，不动的节点证据仍然被接受。

## 数据结构与形态

改动前：

```python
EvidenceEnvironmentIdentity(
    deterministic_runtime_digest: Digest,
    agent_environment: AgentEnvironment | None,
)
```

改动后：

```python
EvidenceEnvironmentIdentity(
    operation_digests: Mapping[OperationID, Digest],
    agent_environment: AgentEnvironment | None,
)
```

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_execution_identity.py
python3 Scripts/rules/test_regression_core_runtime.py
python3 Scripts/rules/verify_regression_core_layering.py
```

运行时：

```sh
python3 Scripts/regression/runctl.py freeze \
  --artifact-root .scratch/harness-tools \
  --simulator-target <模拟器 UDID> --device-target <真机 UDID> \
  --agent-model <模型> --output execution-input.json

python3 Scripts/regression/runctl.py compile \
  --reviews-root Regression/reviews \
  --execution-input .scratch/harness-tools/execution-input.json \
  --output .scratch/harness-tools/plan-a.json
```

改一个 Operation 实现的一行，重跑 `freeze` 与 `compile`，比较两份计划：只有用到该 Operation 的节点其 `evidenceEnvironmentDigest` 相关绑定改变，其余节点逐字节不变。这是失效粒度的直接证明，不需要设备。
