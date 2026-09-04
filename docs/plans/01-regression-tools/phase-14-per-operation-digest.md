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

## 与原清单的偏离

四处：

- **digest 按 handler 的源码段算，不按 locator 的文件算。** 35 个 Operation 合同的 `implementation.locator` 全部指向同一个文件 `Scripts/verification/regression_operation_adapter.py`。按文件算，任何一次 adapter 修改都会同时改动 35 个 digest，阶段目标「一次 harness 修复只失效用过该 Operation 的节点」一次也达不到。改为：每个 Operation 的 digest 由三部分组成——`ResidentOperationBackend` 里 `resident_handler_name(operation)` 那个方法的源码段、把全部 handler 段抽掉之后的其余运行时源码的 digest、以及该 Operation 的合同 digest。实测：改一个 handler 只改一个 digest，改 handler 之外的共享代码改全部 35 个。
- **抽掉 handler 时按段替换而不是按行置空。** 先写成把 handler 的行逐行置空，结果 handler 多一行，被置空的行数也多一行，共享部分的字节数随之改变，35 个 digest 又一起变了。现在整段替换成一行标记，共享部分与 handler 的长度无关。
- **粒度落在节点身上，运行时的比对一行不改。** `runtime.py:1378` 比的是 `node.evidence_environment_identity.digest`，一个节点一个 digest。编译器给每个节点绑定的是**收窄到该节点自己那些 call 所用 Operation** 的身份（`EvidenceEnvironmentIdentity.narrowed`），因此粒度由「节点的身份怎么算」承担，比对逻辑不需要知道这件事。收窄时若某个 Operation 没有 digest，直接拒绝：一个没被摘过实现指纹的 Operation，其证据身份无从谈起。
- **冻结时读 Catalog。** 冻结要知道 Operation 的集合才能逐个算 digest，所以 `_freeze_current` 现在从 `repository/Regression` 加载 Catalog。自测用 `patch.object` 替换 `operation_implementation_digests`，不为此在合成仓库里造一整份 Catalog。

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
