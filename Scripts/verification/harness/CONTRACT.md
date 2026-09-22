# Regression harness 契约

`Scripts/verification/harness/` 是回归 harness 的失败模型、等待策略、超时预算与恢复策略的唯一归属地，本文件是这个包在用的契约。改动包内实现，或改动调用方使用它的方式，都要先满足本文。实现与本文冲突即为缺陷：同一次改动里要么改实现、要么改本文，不留矛盾；无法自行裁决的矛盾向协调者提问。本文的由来见文末。

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
- 五个驱动器已迁移为本包的调用方：`Scripts/verification/reachability_matrix.py`、`Scripts/verification/playback_mode_matrix.py`、`Scripts/verification/measure_controls_flash.py`、`Scripts/verification/regression_operation_adapter.py` 与 `Scripts/regression/tools/op_tool.py`，它们经本包取预算、发动作、判失败。

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

两份 kind 清单的权威是 `Scripts/verification/harness/failures.py` 的 `INSTRUMENT_KINDS` 与 `PRODUCT_KINDS`，本文与代码同步列出。

仪器故障 kind 十项：`transport-timeout`（调用方库观测到的 subprocess 超时）、`response-timeout`（runner 自身的应答死线到期，由 runner 以 instrument 类发出）、`runner-crashed`（非零退出且无可解析 JSON）、`response-undecodable`（JSON 解码失败）、`contract-mismatch`（退出码与 JSON 内 success 字段矛盾）、`wait-expired`（等待原语到期）、`app-not-running`、`session-lost`、`provisional-budget-expired`、`evidence-destroyed`（证据作用域内声明了销毁）。产品失败 kind 两项：`assertion-mismatch` 与 `app-crashed`。

`ControllerClient` 原样转抛 runner 给出的 kind，因此 runner 端新增的 kind 会在不进入 `INSTRUMENT_KINDS` 的情况下到达调用方；`runner-gone` 目前就是这样一项（runner 在 `stage == "runnerGone"` 时发出，class 为 instrument，清单里没有它）。按 kind 分支的调用方按此实际取值对账，不要以清单为穷举。

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
- kind→class 映射由 runner 的 `_attach_failure` 一处计算：`app-crashed`（正向证据是 journal 崩溃记录）与 `assertion-mismatch` 为 product，其余一律 instrument，`response-timeout`、`app-not-running`、`session-lost` 因此都是 instrument。
- 退出码契约不变：0 成功、1 未捕获异常、2 `success: false`。

## 预算（harness/budgets.py）

- 时长样本按 lane 分文件：`Scripts/verification/controller_timings.device.json` 与 `controller_timings.simulator.json`。旧的合并文件 `controller_timings.json`（`simulator:` 前缀区分 lane）由一次性迁移脚本拆分后删除，迁移脚本随 runner 改动交付。
- 新样本格式，每 verb 上限 40 条，先进先出：

```json
{"verbs": {"<verb>": {"samples": [{"seconds": 6.01, "censored": false, "at": "<ISO8601>"}]}}, "updatedAt": "<ISO8601>"}
```

- `censored: true` 表示该次动作在预算内未完成，`seconds` 记录的是预算值（下界）。成功与失败都记样本；旧代码只记成功的偏差就此修正。
- `BudgetProvider.budget(lane, verb) -> Budget(seconds, provenance)`。导出规则：非删失与删失样本合并取 p95，乘系数 1.5，夹在 [5s, 600s]。`provenance` 是人读字符串，格式 `p95 <x>s × 1.5, lane=<lane>, n=<n>, censored=<c>`，出现在每条超时报错里。
- 样本数不足 5 时查临时预算表 `Scripts/verification/harness/provisional_budgets.json`：`{"<verb>": {"seconds": <n>, "expires": "<日期>"}}`。条目可再带 `floorSeconds`：样本足够时导出的预算低于它就抬到它，`Budget.at_floor` 记录这次抬升。已过期→抛 `InstrumentFault("provisional-budget-expired")`；无条目→抛同类故障。
- 表内还有一个非 verb 的顶层键 `_expiry`，值是说明字符串，内容与下一节一致。`BudgetProvider` 只按 verb 名取条目，取到的值不是对象即按无条目处理，这个键因此不会被当成预算。

### 临时预算的统一到期日

表内 63 个条目共用同一个到期日 `2026-10-01`，没有分批。`BudgetProvider.provisional_budget` 的判据是 `today() >= expires`，2026-10-01 当天条目即为过期。

此后任何在该 lane 实测样本不足 5 条的 verb，一取预算就抛 `InstrumentFault("provisional-budget-expired")`。这是仪器故障，不是产品失败：当前段落的观测整体作废并进入恢复，同一位置同一 kind 连续第二次由 `RecoveryPolicy` 判 `Halt`。截至 2026-09-11，device lane 有 36 个、simulator lane 有 50 个条目的实测样本不足 5 条。

到期日按测量债到期设定。消解方式是把样本测够 5 条，让预算改由测量导出；整体顺延日期不构成消解。

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

检查器 `Scripts/rules/harness_primitives_gate.py`：

- 扫描 `Scripts/verification` 与 `Scripts/regression` 下的 Python 文件，禁止出现 `subprocess`、`timeout=`、`time.sleep`、`time.monotonic`、`devicectl` 字样。
- 豁免：`harness/` 包自身、`interactive_visionpro_ui.py`、`enchron_target.py`，以及允许清单 `Config/harness_primitives_allowlist.json` 中列出的文件。清单内容是仍直接持有原语的现存文件；每完成一个迁移就删一行，清单清空后检查器即为无例外强制。
- 检查器风格、注册方式与测试跟随 `Scripts/rules` 现有惯例；必须自带能证明「会拒绝坏输入」的测试。

## 通用要求

- 单元测试纯 Python 可跑，不依赖模拟器或真机；跟随仓库现有测试惯例。本包的测试是 `Scripts/rules/tests/test_harness_library.py` 与 `Scripts/rules/tests/test_budget_ceiling_timing_samples.py`。
- 提交信息遵循仓库现有风格（一行祈使句主题）。

## 由来

本文最初是 harness 重构期间（Wave 1）所有实现工作的规范源，计划在重构完成后分流进 `ARCHITECTURE.md`、`docs/UI_TEST_HARNESS_CONSTRAINTS.md` 与 `.agents/skills/vp-e2e`，本文件随之删除。分流没有发生，包已投入使用，本文就地转为该包的常设契约。重构期的两条规则随之失效：驱动器迁移不再有「不在 Wave 1 范围」的部分；本文件不得修改的冻结令解除，改为与实现同步维护。
