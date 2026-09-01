# Regression harness 契约

本文件是 harness 重构期间所有实现工作的规范源。实现与本文冲突时，以本文为准；认为本文有误时，向协调者提问，不得自行偏离。重构完成后本文内容将分流进 `ARCHITECTURE.md`、`docs/UI_TEST_HARNESS_CONSTRAINTS.md` 与 `.agents/skills/vp-e2e`，本文件随之删除。

## 背景判定（已敲定，不再讨论）

- 每个 runner 动作只有两种终态：带正向证据的成功，或带类型的失败。超时不是判决，是取证触发器。
- 失败分两类：产品失败（product）是有效证据，记录后继续；仪器故障（instrument）宣告后续观测不可信，终止当前段落并进入恢复。
- 分类权分层：runner 报告它能观测到的失败；调用方库只补判 runner 自身死亡的情形（进程崩溃、JSON 不可解码、subprocess 超时），这些天然是仪器故障。
- 产品失败以强类型值返回；仪器故障以异常抛出。
- 超时预算一律由测量导出，禁止手写字面量。
- 全部新代码零注释。无法用代码表达的约束写进本文件；断言信息与日志字符串承担行内文档职责。

## 目录与所有权

- `Scripts/verification/harness/`：本包，唯一的等待策略、预算、失败分类、恢复策略归属地。
- `Scripts/verification/interactive_visionpro_ui.py`：唯一 runner，进程级动作执行者。
- 五个驱动器（`reachability_matrix`、`playback_mode_matrix`、`measure_controls_flash`、两个 regression adapter）后续逐个迁移为 harness 包的调用方，迁移不在 Wave 1 范围。

## 失败领域模型（harness/failures.py）

```python
FailureClass = Literal["product", "instrument"]

@dataclass(frozen=True)
class ProductFailure:
    kind: str
    evidence: dict[str, object]

class InstrumentFault(Exception):
    kind: str
    evidence: dict[str, object]
    budget: Budget | None
```

仪器故障 kind 至少包含：`transport-timeout`（subprocess 超时）、`runner-crashed`（非零退出且无可解析 JSON）、`response-undecodable`（JSON 解码失败）、`contract-mismatch`（退出码与 JSON 内 success 字段矛盾）、`wait-expired`（等待原语到期）、`app-not-running`、`session-lost`、`authorization-required`、`provisional-budget-expired`。产品失败 kind 由判决层定义，Wave 1 只需要 `assertion-mismatch` 与 `app-crashed` 两个内建值。

## Runner 结构化失败输出（interactive_visionpro_ui.py）

runner 输出的 JSON 文档在失败时必须携带：

```json
"failure": {
  "class": "product" | "instrument",
  "kind": "<上表中的 slug>",
  "evidence": {"diagnosis": "...", "observations": [...]}
}
```

- 现有 `explain_failure` 的 prose 诊断保留，移入 `evidence.diagnosis`。
- 现有 `timeout_observations` 的产物移入 `evidence.observations`。
- kind→class 映射：`app-crashed` 为 product（正向证据是 journal 崩溃记录）；`response-timeout`、`app-not-running`、`session-lost`、`authorization-required` 为 instrument。
- 退出码契约不变：0 成功、1 未捕获异常、2 `success: false`。

## 预算（harness/budgets.py）

- 时长样本按 lane 分文件：`Scripts/verification/controller_timings.device.json` 与 `controller_timings.simulator.json`。旧的合并文件 `controller_timings.json`（`simulator:` 前缀区分 lane）由一次性迁移脚本拆分后删除，迁移脚本随 runner 改动交付。
- 新样本格式，每 verb 上限 40 条，先进先出：

```json
{"verbs": {"<verb>": {"samples": [{"seconds": 6.01, "censored": false, "at": "<ISO8601>"}]}}, "updatedAt": "<ISO8601>"}
```

- `censored: true` 表示该次动作在预算内未完成，`seconds` 记录的是预算值（下界）。成功与失败都记样本；旧代码只记成功的偏差就此修正。
- `BudgetProvider.budget(lane, verb) -> Budget(seconds, provenance)`。导出规则：非删失与删失样本合并取 p95，乘系数 1.5，夹在 [5s, 600s]。`provenance` 是人读字符串，格式 `p95 <x>s × 1.5, lane=<lane>, n=<n>, censored=<c>`，出现在每条超时报错里。
- 样本数不足 5 时查临时预算表 `Scripts/verification/harness/provisional_budgets.json`：`{"<verb>": {"seconds": <n>, "expires": "<日期>"}}`。已过期→抛 `InstrumentFault("provisional-budget-expired")`；无条目→抛同类故障。临时表初始内容：`halt` 60s、`ensure-session` 300s、`probe-copy` 120s，到期日一律 2026-10-01。

## 控制器调用（harness/controller.py）

`ControllerClient(lane).invoke(verb, arguments) -> RunnerResponse`：

- 预算取自 `BudgetProvider`，不接受调用方传入的超时值。
- subprocess 超时→记删失样本→抛 `transport-timeout`。
- 退出码与解析出的 JSON 逐项对账；矛盾→抛 `contract-mismatch`。
- runner 报 instrument 类失败→转抛对应 `InstrumentFault`；报 product 类失败→返回含 `ProductFailure` 的响应，不抛。
- 每次调用记一条样本（成功记实测时长，失败记实测时长，超时记删失）。

## 等待原语（harness/waits.py）

```python
def wait_for(label, probe, budget, observe) -> Evidence
```

- `probe()` 返回证据即满足；到期时调用 `observe()` 采集现场，抛 `InstrumentFault("wait-expired")`，evidence 携带 label、观测结果与预算出处。
- 不存在返回「最后一份快照」的路径。`reachability_matrix.wait_for_*` 的静默到期模式被此原语取代后即为禁止形态。
- 每次等待记样本，label 即 verb。

## 证据作用域（harness/evidence.py）

- `EvidenceScope` 上下文管理器：进入时归档并清空探针日志与响应批次；退出时封存。
- 恢复动作必须经 `scope.register_destruction(<描述>)` 声明其销毁物；在作用域内发生销毁即抛 `InstrumentFault`，该段证据整体作废，段落重跑。

## 恢复策略（harness/recovery.py）

`RecoveryPolicy.on_fault(fault, history) -> Retry | Halt`：

- 同一位置同一 kind 连续第二次→`Halt`（确定性，harness 缺陷，不再重试烧时间）。
- 样本删失即视为失准信号，交测量流修正，本次按瞬态处理。
- 其余首次出现→`Retry`（至多一次恢复，恢复动作由调用方提供，如 ensure-session）。
- 每次 `Halt` 的报告必须含故障率统计（本轮 instrument 故障数/动作总数）。

## 原语门禁（Scripts/rules/）

新增检查器 `harness_primitives_gate.py`：

- 扫描 `Scripts/verification` 与 `Scripts/regression` 下的 Python 文件，禁止出现 `subprocess`、`timeout=`、`time.sleep`、`time.monotonic`、`devicectl` 字样。
- 豁免：`harness/` 包自身、`interactive_visionpro_ui.py`、`enchron_target.py`，以及允许清单 `Config/harness_primitives_allowlist.json` 中列出的文件。清单初始内容为五个驱动器与其余现存违例文件；每完成一个迁移就删一行，清单清空后检查器即为无例外强制。
- 检查器风格、注册方式与测试跟随 `Scripts/rules` 现有惯例；必须自带能证明「会拒绝坏输入」的测试。

## 通用要求

- 单元测试纯 Python 可跑，不依赖模拟器或真机；跟随仓库现有测试惯例。
- 提交信息遵循仓库现有风格（一行祈使句主题）。
- 不修改本文件。发现矛盾用 ask 上报。
