[← overview](overview.md)

# 阶段 15：已知缺陷账本

## 目标

Scenario 层的已知缺陷账本，终态 `failed(known)` 不阻塞收据。已知缺陷与普通失败在账本上是两个不同的终态，不是同一个终态加一条豁免注释。

## 前置阻塞：账本里没有第二次 attempt

`_claim_node` 要求节点处于 `PENDING`（`Scripts/regression/core/runview.py:1131`），而 `runtime.py` 里没有任何路径把节点写回 `PENDING`：状态只会向终态推进。因此一次 run 内一个节点只能被 claim 一次，本阶段与阶段 16 所依赖的「同一节点连续两次 attempt」在当前状态机下无法出现。这一项在阶段 12 实现 `bundle --attempt` 时暴露（见[阶段 12](phase-12-bundle-tool.md) 的偏离一节）。

### 选定：裁决之后由账本显式重开节点

- **甲，重开写进账本。** 新增事件 `NODE_REOPENED`。它只接受一种前置状态：节点为 `INDETERMINATE`，且它的裁决归因为 `harness`。重开把节点写回 `PENDING`，上一次的 lease 保持终态不变，新一次 claim 起一个新的 lease。attempt 因此是该节点 lease 的序号，可从账本读出，`bundle --attempt` 与 `deferrable` 都有据可依。上限两次：第三次重开被拒，节点只能走 `deferred(human)` 或 `failed`。
- **乙，attempt 跨 run。** `deferrable` 要读别的 run 目录才能数出两次 attempt，收据层也要跨 run 聚合。它把一个本可以留在单个 append-only 账本内的事实拆到多个文件之间，且没有任何机制保证那些 run 属于同一份计划。

选甲。重开是一个独立的事实，不是裁决的一种；把它写成事件而不是复用裁决事件，使「这个节点被重开过几次」可以从事件流直接数出来，也让转移规则留在 `_record_verdict` 旁边的同一张表里。归因限定为 `harness` 是这条出口的护栏：产品失败与 spec 失败不重试，它们的终态就是结论。

本阶段与阶段 16 合并前须走 **interrogate**：它改变「什么情况下允许继续跑」，与阶段 8 的账本锁属于同一类判断。

## 改动清单

- 新增 `Config/regression/known_defects.json`。逐条：Scenario ID、缺陷描述、命中判据（签名 id 或字段谓词）、录入日期、失效条件。失效条件是这条记录何时必须被重新审视，留空即拒绝录入。
- 新增 `Scripts/regression/tools/known_defects.py`。一个函数 `classify(verdict, fields) -> NodeStatus`。命中账本中某条记录的判据时返回 `FAILED_KNOWN`，否则返回 `FAILED`。命中判定用签名 id 或阶段 13 的 `FieldPredicate`，不用自由文本匹配。
- `Scripts/regression/tools/ledger_tool.py`。`write` 动作在写入 `FAILED` 之前先过 `classify`。
- 新增 `Scripts/rules/test_regression_known_defects.py`。覆盖：命中记录写入 `failed(known)`、未命中写入 `failed`、缺 `失效条件` 的记录被拒、`failed(known)` 不进入 lane 锁的待裁决集合、`failed(known)` 不阻塞收据。

新增的 Python 文件不得含注释。

## 数据结构与形态

```python
KnownDefect(
    scenario: ScenarioID,
    description: str,
    match: SignatureID | FieldPredicate,
    recorded: date,
    expires_when: str,
)

classify(verdict: Verdict, fields: Mapping[str, Any]) -> NodeStatus
```

## 与原清单的偏离

九处：

- **重开暴露了四处「一个节点只被 claim 一次」的下游假设，全部在本阶段修掉。** 对抗审查逐条跑出来的：
  - `runtime.py` 的恢复循环按**节点**状态判断要不要恢复一个 lease（`:1680`）。第二次 attempt 让节点重新变成 `LEASED` 之后，第一次那条已经 `INTERRUPTED` 的 lease 也通过了这道判断，于是下一次 `open_run` 就把 lane 打断——实测 12 次里 12 次，而每一次 `op` 调用都会 `open_run`。判断改为同时要求这条 lease 就是节点当前持有的那条。
  - 三处用 `node_id` 去取「这个节点的 lease」，而 `RunView.leases` 按 lease id 排序，lease id 是 digest 前缀，排序与 claim 顺序无关。审查员在 2000 个合成 run id 上量到第一次 attempt 排在前面的比例是 975/2000。取错的后果是拿第一次的 Oracle 结果去裁决第二次，节点因此既关不掉也 finalize 不了。改为一律走 `current_lease`（节点自己记着它当前的 lease）。
  - `bundle --attempt n` 同样按排序取，`--attempt 1` 有 4/10 拿到第二次。`LeaseView` 增 `claim_sequence`，attempt 按 claim 顺序取。
  - `failed(known)` 在 `finalize` 的结局阶梯里没有分支，落到末尾的 `else` 判成 `INTERRUPTED`——本阶段要产出的那个状态，恰好让整轮 run 被判为中断。补上分支。
- **重开保留裁决，并拒绝所有候选 lane 都已中断的节点。** 原先重开把 `adjudication` 清掉，而它是这个节点被送回来的唯一原因记录；`projection` 也只读这一个字段。若重开发生在一条已中断的 lane 上，节点会停在 `PENDING` 且没有任何 lane 能 claim 它，`resume` 既不报 ready 也不报待裁决，那条裁决就此消失。现在裁决留着，全部候选 lane 都中断时直接拒绝重开。
- **`attemptsBefore` 在回放时被核对。** 它原本只写不读，一条声称 `attemptsBefore: 0` 的伪造事件能干净回放。阶段 8 的原则是伪造的账本回放不过去，这个字段得对得上 lease 数。
- **重开机制与本阶段同批落地。** 前置阻塞一节选定的 `NODE_REOPENED` 是本阶段的一部分：`events.py` 增该事件，`runview.py` 增 `reopen_refusal` 与 `_reopen_node`，`ledger_lock.py` 增 `admit_reopen` 与 `attempts`，`ledger_tool.py` 增 `reopen`，`server.py` 的 ledger 动作增 `reopen`。没有它，本阶段与阶段 16 都无从谈起。
- **裁决事件的幂等键带上 attempt。** 原先是 `verdict:<node>`，一个节点重开之后写第二次裁决会撞上 `ledger.idempotency_conflict`。这一条是账本自己在自测里抓出来的：键必须是 `verdict:<node>:<attempt>`。
- **判定所读的每一项都取自这次运行本身，不接受调用方的声明。** 起初 Scenario 与字段读数是 `write` 的两个参数，理由写的是「run 目录里没有计划」——这句话是错的：`_write_plan_once`（`runtime.py:1926`）把 `plan.json` 落在 run 目录里，每个节点的 payload 带着 `scenarioId`（`plan.py:1366`）。对抗审查指出，只要这两项由调用方给，记录里的 `scenario` 就不是作用域约束而是一句口令：谁打对那串字符，谁就拿到那条豁免。现在 Scenario 从 `plan.json` 按节点查出，字段读数从该节点 lease 最后一次完成调用的 `outputs` 取出，两个参数都删掉了。
- **`failed(known)` 不接受调用方点名。** 它原本是 `NodeStatus` 里一个普通取值，调用方直接传就绕过 `classify`，账本上留下的事件与一次真正的豁免逐字节相同。现在 `write` 直接拒绝这个状态，MCP schema 的 enum 里也不再列出它：它只能由已知缺陷账本推导出来。
- **字段匹配与 op 的 L0 读数共用同一个查找函数。** 两处原本一个扁平查找、一个递归查找，同一份 `outputs` 会得出不同结论，把操作者推向手工摊平字典或改用签名匹配——那两条恰好是未经核对的路径。
- **匹配只认注册表内的签名 id 与 `field == value`。** 不接受其他比较符：一条 `!=` 记录能豁免的失败范围比它描述的缺陷大得多。自由文本不进匹配判据。

`Config/regression/known_defects.json` 以空表落地。第一条记录由真正遇到已知缺陷的那次运行录入，而不是为了让表非空而预填。

## 未闭合的缺口

对抗审查列出的以下几项本阶段没有关闭，逐条记在这里而不是留给下一个人重新发现：

- **`verdict.signature` 与运行期实际命中的签名之间没有绑定。** `op` 的 `pixel_signatures` 与 `bundle` 的 `frame_unchanged` 算出的签名都没有进账本，因此账本里根本没有可比对的一侧。要闭合它，得先把算出的签名写成事件或写进完成事件的保留键，再让 `write` 拒绝一个不在该节点该次 attempt 命中集合里的签名。
- ~~**豁免的依据不进账本。**~~ 2026-09-05 闭合。`adjudication` 增加 `knownDefect` 键，写下豁免这个节点的记录的 Scenario 与它的命中判据。replay 据此校验：`failed(known)` 必须带这个键，其他终态不得带；判据是签名 id 时它必须等于裁决里的签名。同一次改动修掉一个死锁——`classify` 判出 `failed(known)` 之后，`admit_verdict` 与 replay 都要求裁决带签名，而按字段谓词命中的记录并不产生签名，那个节点因此既写不成 `failed(known)`（缺签名被拒）也写不成 `failed`（`classify` 会覆盖），无法收口。
- **`expiresWhen` 只要求非空文本。** 它没有任何检查方式，也没有任何地方再读它。可检查的替代是一个必填的 `expiresOn` 日期，`load` 在过期时拒绝；`recorded` 已经按 ISO 解析，也可以据此设一个最长年龄。
- **没有登记的 ratchet 检查看住这张表。** 阶段 13 的覆盖率基线是同一个机制的反向用法：那里下限只能升，这里条数只能降。表目前为空，第一条记录落地之前补上这道门是自然的时机。
- **一条范围划错的豁免影响整棵下游子树。** `failed(known)` 现在与 `failed` 一样进入 `failure_ancestors`（`Scripts/regression/core/runview.py:628`），下游节点因此被派生为 `blockedBy` 并随 run 一同收口。这条记账原先写的是相反的因果——「不进 `failure_ancestors`，因此不阻塞下游」。实测那个版本的后果不是放行而是冻结：下游节点拿不到派生裁决，停在 `PENDING`，收口时变成 `indeterminate`，收据被拒。代价仍在，形状不同：豁免划错时，被判成 `blockedBy` 的是一整棵本可以跑的子树。

### 独立审计追加的缺口

合并之后一次独立审计（2026-09-05）在阶段 10 到 19 的工具层找到下列几项，已修的不在此列：

- **`field_value` 是无锚点的深度优先首命中查找。** 一条判据无从表达它问的是哪个元素、哪一次调用。`op` 的 L0 读数与已知缺陷豁免的字段匹配共用它，因此豁免的作用范围由同一次首命中决定。闭合它要给判据一个锚（调用 id 加字段路径），属于阶段 13 编译器的形状。
- **48 条 L0 谓词里 30 条命名的是 Operation 的入参而非输出。** `requireMatchedElement` 出现在 `regression_operation_adapter.py:2807` 的参数里，不在任何返回的 outputs 中，因此这些谓词恒为 `indeterminate`。`Config/rubric_predicate_baseline.json` 的 `criteriaYieldingPredicates: 47` 把这个数字锁住了：一次「不再把入参名编译成观测」的修正会被该门拒绝，需要同时下调基线。
- **`negativeControls` 没有被编译器读取。** 阶段 13 的改动清单写的是「只读 front matter 里的 `criteria` 与 `negativeControls`」，实际只读 `criteria`。覆盖报告的分母因此不含 negative controls。
- **人类会话的轮询回路没有接线。** `poll_timeline`、`mark`、`read_timeline` 三个函数只有测试调用；MCP 的 `session` schema 没有 `mark` 动作，也没有任何一处驱动轮询。`ensure` 现在会开出 `timeline.jsonl` 并写入第一行，路径不再指向不存在的文件，但佩戴者回路本身仍是空的。
- **仪器故障的整个 evidence 字典进了账本。** `op_tool` 把 `InstrumentFault` 合成为一次完成的调用，`outputs.failure.evidence` 是 harness 自己写的内容而不是 Operation 输出合同的一部分，`invoke_operation` 也不按输出形状校验它。它随后可被 `field_value` 检索，而那正是 L0 读数与已知缺陷豁免共用的匹配函数。阶段 16 需要的是故障 kind，落到账本里的是整个故障。
- **`--catalog-root` 与 digest 计算的 Catalog 不是同一个。** `execution_identity` 两处都写死 `Regression`，`op` 却接受任意 `catalogRoot`。两者持有不同 Operation 集合时 `narrowed()` 会拒绝——方向是安全的——但操作者读到的是「冻结环境里没有某个 Operation 的 digest」，而不是「你指错了 Catalog」。
- **异常包的 before 帧可能来自另一个 Operation。** 它取的是上一次完成调用的截图，标题原先写的是失败调用的 call id；标题已改成那张图真正的来源。Agent 仍需要知道这两帧可能横跨两个 Operation。
- **人类收据没有 run 绑定。** 收据现在必须匹配本次 run 生成的 checklist digest（`Scripts/regression/tools/receipt_tool.py`），但收据里的 `buildDigest`、`deviceId`、`recordingDigest` 依然没有任何一侧可比对，`seal` 也没有工具入口，操作者实际走的是手写 JSON 这条路。

### 计划要求但没有执行的门

`overview.md:118` 与本文件开头都要求本阶段与阶段 16 合并前走 **interrogate**。该技能保留给使用者显式调用，Agent 无法代为发起。合并前实际执行的是两轮派遣式对抗审查（豁免路径与重开路径），各找出 1 个 critical 与若干 high 并当场修掉；这不等同于计划指定的那道门。需要补的话由使用者运行 `/interrogate`。

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_regression_known_defects.py
python3 Scripts/rules/test_regression_ledger_lock.py
```

运行时（模拟器 lane）：

```sh
python3 Scripts/regression/tools/server.py --once op \
  --plan .scratch/harness-tools/plan.json \
  --run-directory .scratch/harness-tools/run \
  --node <已录入已知缺陷的 NodeID> --call <CallID>

python3 Scripts/regression/tools/server.py --once ledger \
  --run-directory .scratch/harness-tools/run --view
```

对一个已录入的 Scenario 跑一次 op，账本视图中该节点为 `failed(known)`，且它所在 lane 的 `LaneLock.locked` 为假。这一对返回值证明已知缺陷既被记录也不挡路。
