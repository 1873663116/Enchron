[← overview](overview.md)

# 阶段 4：拆出 agent identity，删 AgentOracleProvider

## 目标

删掉以子进程调用固定模型做 Oracle 判读的 provider。判读改为三级：L0 字段谓词、L1 像素启发、L2 交互中的 Agent。`EvidenceEnvironmentIdentity` 仍需绑定 Agent 环境身份，因此把身份计算从 provider 中拆出来单独成模块。

## 改动清单

- 新增 `Scripts/regression/agent_identity.py`。从 `Scripts/regression/oracle_agent.py` 迁入 `agent_environment(model, executable) -> AgentEnvironment`（:119-135）及其依赖的 `PROTOCOL_VERSION`、`PROMPT_PROTOCOL`、`DECISION_SCHEMA` 与 `_command`。只算 digest，不起进程。文件内不得含注释，模型与命令的取值来源写进常量名。
- `Scripts/regression/execution_identity.py`。把 :32 的 `from regression.oracle_agent import agent_environment` 改为 `from regression.agent_identity import agent_environment`。调用点 :1798 与 :2296 不变。
- 删 `Scripts/regression/oracle_agent.py`（340 行）中的 `AgentOracleProvider`（:138 起）与其子进程 runner；文件被 `agent_identity.py` 取代后整体删除。
- `Scripts/rules/test_regression_oracle_agent.py`（230 行）。绑定 provider 行为的用例随之删除；绑定 `agent_environment` digest 稳定性的用例改名迁到 `Scripts/rules/test_regression_agent_identity.py`。
- `Config/harness_primitives_allowlist.json`。删 `Scripts/regression/oracle_agent.py` 一行（:4），增 `Scripts/regression/agent_identity.py`。

`Scripts/regression/core/runtime.py:1632` 的错误码字符串 `runtime.oracle_agent_environment_mismatch` 是 `EvidenceEnvironmentIdentity` 比对失败的编码，与被删的 provider 无关，保留。`Scripts/rules/test_regression_core_runtime.py:600` 断言该错误码，同样保留。

## 数据结构与形态

```python
AgentEnvironment(model: str, prompt_digest: Digest, configuration_digest: Digest)
agent_environment(model: str, executable: str = "codex") -> AgentEnvironment
```

`AgentEnvironment` 的定义留在 `Scripts/regression/core/plan.py:296`，本阶段不动。

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_agent_identity.py
python3 Scripts/rules/test_regression_execution_identity.py
python3 Scripts/rules/harness_primitives_gate.py
```

运行时：

```sh
python3 Scripts/regression/runctl.py freeze \
  --artifact-root .scratch/harness-tools \
  --simulator-target <模拟器 UDID> --device-target <真机 UDID> \
  --agent-model <模型> --output execution-input.json
```

冻结成功并写出与迁移前逐字节相同的 `evidenceEnvironmentDigest`，证明身份计算在搬家后没变。这条命令不驱动设备，但它是 `EvidenceEnvironmentIdentity` 唯一的生产路径。
