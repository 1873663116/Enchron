[← overview](overview.md)

# Interrogate：阶段 8、15、16（2026-09-05）

计划要求账本锁、已知缺陷账本与人类层合并前走 interrogate。该门于 2026-09-05 补跑：四位审查者（三个 opus、一个 sonnet）收到同一份 prompt——三条规则的意图、待审文件、量规——对当前工作树只读审查，每条发现须附可运行的复现或变异证据。本文是主评审的裁决与处置记录。

## 改动意图

> 账本新增三条「什么情况下允许继续跑」的规则，三条都在回放层成立：账本锁（非 Satisfied 的 attempt 把节点停在 `leased`，lane 拒绝下一次 claim，直到裁决到达；裁决准入由聚合结果给出；伪造的账本行回放不过去）、已知缺陷账本（`failed(known)` 由注册表推导，`adjudication` 带 `knownDefect`，`NODE_REOPENED` 只接受归因 harness 的 `indeterminate`、上限两次）、人类层（`deferred(human)` 仅当同一节点连续两次 attempt 均为 `HARNESS_TIMEOUT_KINDS`）。贯穿原则：账本不采信裁决 Agent 对任何可从 run 读出的事实的自述。

## 审查者矩阵

- A（opus）：14 项，5 critical。
- B（opus）：12 项，3 critical。
- C（opus）：11 项，4 critical。
- D（sonnet）：5 项，2 critical。

## Must address

每一项都附了复现输出；除 M4 外都是同一个根因的实例：`admit_verdict` 拒绝的裁决，直接追加成账本行就能回放通过。

| # | 缺陷 | 提出者 | 处置 |
|---|---|---|---|
| M1 | `failed(known)` 的 `knownDefect` 在回放层只查形状：不查 Scenario、不查比较符、不重算字段谓词。伪造一行把真实失败翻成 `passed`。 | A B C D | 已修。`RUN_OPENED` 节点 payload 带 `scenarioId`；`_verify_exemption` 要求 Scenario 相等、比较符为 `==`、对该 lease 最后一次完成调用的 outputs 重算命中、按类型严格比较。注册表成员资格不在回放层重查（注册表是配置，账本自含）。 |
| M2 | `deferrable_from` 与「结果尚未定只许 indeterminate」都写在 `LEASED` 分支内；`PENDING` 节点可写成 `deferred(human)`，前驱全 `PENDING` 的 join 可写成 `passed`，刚 claim 的 lease 可写成 `blockedBy`。 | A B C | 已修。准入表 `admissible_verdicts` 一张，回放与工具共用；无 lease 的节点只接受 `indeterminate` 或与 `derivable_verdict` 逐项相等的派生结论。 |
| M3 | `blockedBy` 的 `failureAncestors` 只做标识符解析，可指向不存在的节点，沿子树传播，整轮收口 `passed` 并出收据。 | A B C | 已修。祖先集合必须等于 `derivable_verdict` 的结果。 |
| M4 | 人类层生产路径不可达：仪器故障 → `succeeded=False` → cursor 不前进 → `maxInvocations` 全为 1 → `interrupt_lane` → 无 adjudication 的 `indeterminate` → `reopen_refusal` 拒。自测用的是 `op_tool` 从不产出的形状。 | A C D（B4 相关） | 已修。终局调用以仪器故障收场且不再允许重试的 attempt 走账本锁：节点停在 `LEASED`，lane 不中断，裁决只许归因 harness 的 `indeterminate`／`deferred(human)`；`deferrable` 只读终局调用（B4）；`DeferrableTests` 改用真实形状。 |
| M5 | `bundleFrameCount` 回放层由 payload 自述，`firstDeviantFrame` 的边界是自洽校验。 | A B C | 已修。`montage_frame_bound(lease)` 数最后两次完成调用里带截图键的条数，声明值不得超过。 |
| M6 | `runtime._record_verdict` 幂等键无 attempt（C10 D3）；`finalize` 清扫按 lease 排序取到已停掉的第一次 attempt，8/12 把中断记错（C7）。 | C D | 已修。键为 `verdict:<node>:<attempt>`；清扫按节点取 `current_lease`。 |
| M7 | `deferred(human)` 冻结下游子树：后继停在 `PENDING`，`finalize` 写成 `indeterminate`，run 判 `interrupted`，人类收据覆盖不到后继。 | C | 已修。`BLOCKING_NODE_STATUSES` 把它计入祖先，后继派生 `blockedBy`；`RunOutcome` 增 `deferred`。`completion.py` 的 FullRun 完成门仍只接受 `passed`：一轮 `deferred` 的 run 由人类收据关门，不经该门，这是边界而不是遗漏。 |

## Consider

| 缺陷 | 提出者 | 处置 |
|---|---|---|
| `HARNESS_TIMEOUT_KINDS` 四个，意图与阶段 16 文档说三个；文档给出的排除理由（`CONTRACT.md:36` 不含 `response-timeout`）与 `:52` 的 kind→class 映射矛盾。 | A B C D | 保留四个：runner 以 instrument 类发出 `response-timeout`。`INSTRUMENT_KINDS` 补上它，自测钉住 `HARNESS_TIMEOUT_KINDS ⊆ INSTRUMENT_KINDS`；阶段 16 文档改正；`CONTRACT.md` 自身规定不得修改，`:36` 与 `:52` 的矛盾记在阶段 16。 |
| 时间线「时间戳单调」无处执行，自测断言的是注入时钟的性质。 | A B C | `append_entry` 拒绝回退；`read_timeline` 畸形行抛 `SessionToolError`；自测改为注入回拨时钟。 |
| `runtime` 两处手写「聚合是否 SATISFIED」，`AnyOf` 下与 `settled_oracle_result` 不等价。 | B | 两处改调 `settled_oracle_result`。 |
| `reopen_refusal` 的回放层零测试：变异掉它四个套件全绿。 | A | `test_regression_replay_admission.py` 对五种拒绝各追加一行伪造 `NODE_REOPENED`。 |
| `FieldPredicate.value` 无构造校验；`_hits` 用 `==`，`True == 1`。 | A C | 注册表加载只接受 bool 与 str；比较按类型严格。 |
| `attemptsBefore` 用裸 `!=` 核对，`True` 通过。 | B | 改 `_integer`。 |
| 回放层接受全空白 `regionObservation`，工具层拒。 | A | 两层同一判空。 |
| `ledger_lock` 死导入、`__all__` 脱节、`_predecessors_passed` 重写 `strict_predecessors`、重开保留旧 lane、`finalize` 死分支。 | A B C | 全部清理。 |
| `runview.py` 2258 行，三条规则各自往里堆；建议把裁决准入抽成独立模块。 | A D | 本次把准入收成一张表并与工具共用；拆模块不在本次范围，留待下一次触及该文件时做。 |

## Noted

- `failed` 与 `failed(known)` 在收据层等价（A7）。收据的语义是「节点已由账本关闭」，`failed` 本就关闭；差别在 `RunOutcome`。阶段 15 的验证方案措辞已改正。
- `field_value` 无锚点、`recorded_fields` 只取最后一次调用（A11、C）。已记录的缺口，属阶段 13 判据锚定的形状；本次只把查找收成核心层的一份。
- `poll_timeline`／`mark`／`read_timeline` 无工具入口（A9）。已记录。
- `expiresWhen` 无失效机制、注册表无 ratchet（C）。已记录。

## Dismissed

无。每一条发现都附有复现输出或变异证据，主评审逐条核对后没有驳回项。

## Consensus Map

四位审查者在根因上一致：回放层比工具层宽，`knownDefect`、`deferred(human)`、`blockedBy`、`bundleFrameCount` 四处都是工具拒、回放放行。三位独立跑出人类层生产路径不可达，且各自指出自测夹具与 `op_tool` 的返回形状互相矛盾。分歧只在严重度分级：`bundleFrameCount` 一项 A 判 critical，B 与 C 判 warning。sonnet 审查者的五项全部落在 opus 审查者的共识集合内，没有孤立发现。

## 处置后的验证

```sh
python3 Scripts/rules/test_regression_replay_admission.py
python3 Scripts/rules/test_regression_core_runtime.py
python3 Scripts/rules/test_regression_ledger_lock.py
python3 Scripts/rules/test_regression_known_defects.py
python3 Scripts/rules/test_regression_human_session.py
python3 Scripts/rules/run_verification.py --quick
```
