[← overview](overview.md)

# 阶段 4：拆出 agent identity，删 AgentOracleProvider

## 目标

删掉以子进程调用固定模型做 Oracle 判读的 provider。判读改为三级：L0 字段谓词、L1 像素启发、L2 交互中的 Agent。`EvidenceEnvironmentIdentity` 仍需绑定 Agent 环境身份，因此把身份计算从 provider 中拆出来单独成模块。

## 改动清单

- 新增 `Scripts/regression/agent_identity.py`。从 `Scripts/regression/oracle_agent.py` 迁入 `agent_environment(model, executable) -> AgentEnvironment`（:119-135）及其依赖的 `PROTOCOL_VERSION`、`PROMPT_PROTOCOL`、`DECISION_SCHEMA` 与 `_command`。只算 digest，不起进程。文件内不得含注释，模型与命令的取值来源写进常量名。
- `Scripts/regression/execution_identity.py`。把 :32 的 `from regression.oracle_agent import agent_environment` 改为 `from regression.agent_identity import agent_environment`。调用点 :1798 与 :2296 不变。
- 删 `Scripts/regression/oracle_agent.py`（340 行）中的 `AgentOracleProvider`（:138 起）与其子进程 runner；文件被 `agent_identity.py` 取代后整体删除。
- `Scripts/rules/test_regression_oracle_agent.py`（230 行）。绑定 provider 行为的用例随之删除；绑定 `agent_environment` digest 稳定性的用例改名迁到 `Scripts/rules/test_regression_agent_identity.py`。
- `Config/harness_primitives_allowlist.json`。删 `Scripts/regression/oracle_agent.py` 一行（:4）。不增 `Scripts/regression/agent_identity.py`：该文件登记的是允许直接驱动设备的脚本，`harness_primitives_gate.py` 把它当作扫描豁免名单。`oracle_agent.py` 需要豁免是因为它起子进程；`agent_identity.py` 只算 digest，零 `subprocess`、零 `timeout=`、零 `time.sleep`，登记它只会让该文件此后逃过扫描。

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

冻结成功即可，`evidenceEnvironmentDigest` 会变，这不是回归。`EvidenceEnvironmentIdentity` 的 payload 含 `deterministic_runtime_digest`（`execution_identity.py:712`），后者哈希 `Scripts/regression` 与 `Scripts/verification` 下每一个 `.py`，所以任何增删文件的阶段都会移动它。实测本阶段前后为 `sha256:88adf966…` → `sha256:212a0c58…`。这正是 [overview](overview.md) 「失效粒度」一节所指的问题，阶段 14 改为逐 Operation digest 之后才会消失。

本阶段真正要证的是身份计算本身在搬家后没变，判据是 `agent_environment` 的两个 digest 逐字节相同：

```sh
PYTHONPATH=Scripts python3 -c "from regression.agent_identity import agent_environment; e = agent_environment('gpt-5.6-sol', 'codex'); print(e.prompt_digest, e.configuration_digest)"
```

应得 `sha256:5d552a51d085d026ca2c28f3cf3f1e567d0e11ad92dde211e2019e82d999b819` 与 `sha256:80ecb82257e9a498c27312c475e95c200ec706da73648a8e901735c78c95322d`。
