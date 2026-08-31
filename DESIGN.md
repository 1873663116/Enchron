# 让错误的路不可用

## 1. 核心机制

**等待被改造成一个有类型的对象：它必须命名承载完成事实的推送通道才能被打开；打开之后，一个不去读它的回合无法结束。** PreToolUse 在命令执行前拒绝把等待与通道剥离的 shell 形态，Stop 在回合结束前拒绝一个持有未读 watch 的回合。两处都在动作发生之前。

这条机制来自对失效的一次归并。A（无人接续）、B（长延迟停车）、C（监视错误对象）表面上是三种病，实际是同一句话：**这次等待没有绑在会推送的通道上**。绑上了，476 分钟的空窗不会存在，因为通道会叫醒；绑上了，900 秒的武装无害，因为它只是兜底心跳，28 秒时通知先到；绑上了，就不必去数文件、数进程、读 TUI 尾行。而所有把通道弄丢的动作——detacher、无 `--run` 的 `check`、`--peek` 之后单独 `--ack`、`terminal create` 派遣——都在命令文本里可见，因此可以在执行前拒绝。

守卫不劝告。`controller_background_context.py` 是本仓库已有的反例：它注入实测数字然后放行，是"同一教训的 hook 形态但仍是劝告"。本设计里没有一条规则以注入上下文结束。

## 2. 数据形态

### 2.1 协调者账本 `.claude/state/coordinator.json`

一个 worktree 一份，被 `.gitignore` 排除。

```json
{
  "session": "<session_id>",
  "turn": 7,
  "dispatches": [{"turn": 5, "command": "orca orchestration worker-start --task task_a …"}],
  "sweeps":     [{"turn": 6, "kind": "sweep", "closed": 8}],
  "watches": {
    "watch_ca3805b3": {
      "channel": {"kind": "orca-run", "run": "run_88ce8141de0a"},
      "openedTurn": 5,
      "closedTurn": null,
      "observations": [{"turn": 5, "total": 8, "settled": 0, "digest": "1f0c…"}]
    }
  },
  "wakes": [{"at": 1756…, "reason": "watch_ca3805b3: 8/8 dispatches settled"}]
}
```

`turn` 是**推导量，不是戳记**。它由每个写入方从 transcript 里数"真实用户消息"得到，而不是由 Stop hook 自增。理由是第 6 节那个洞：一个根本没执行的回合不跑 Stop hook，戳记会恰好在会话出事时冻结。`session` 变更即整份重置。

### 2.2 watch：唯一合法的等待

`watch` 只接受两种 channel，判据是"它是否推送"：

| kind | 完成事实抵达方式 | 进展计数 |
|---|---|---|
| `orca-run` | `worker_done` 消息 + Orca 会话通知 | `worker-list --run` 的 `dispatchStatus`／`lastHeartbeatAt` 摘要 |
| `background-task` | 运行时的 `<task-notification>` | 无需轮询，推送即到 |

路径、glob、进程表、终端尾行**在 open 时被拒绝**，拒绝语里带着它们各自的实测后果。这是对"文件落盘当 worker 完成"的结构性回答：那条路不是被劝退的，是打不开的。

`observations` 是这套设计里唯一的卡死判据来源，而且**只按样本数计，不按秒计**：`STALE_OBSERVATIONS = 3`，连续三个样本的 digest 完全不变且尚未全部 settled 才判 stalled。这是 `run_workers.py` 实测收敛的值（三次相同 tail），也是唯一不需要先验知道一轮时长的形状。整套代码里没有任何一个秒级卡死阈值。

### 2.3 dispatch 账本与 sweep 的耦合

`worker-start` 由 PreToolUse 记进 `dispatches`；`drain`／`sweep` 把它清空。规则是：**同一回合内可以任意扇出，跨回合再派必须先 sweep。** 由此"读信箱"不再是一件要记得做的事，而是"再派一批"的前置条件。峰值 297 个未释放终端、load 16.9、最后一轮 worker 起不来——这条链在这里被接上了。

### 2.4 变异清单 `.claude/mutations.json`

30 条，每条形如：

```json
{"id": "gate-detach", "file": "hooks/orca_channel_gate.py",
 "find": "DETACHERS = re.compile(…)", "replaceWith": "DETACHERS = re.compile(r\"(?!x)x\")",
 "probe": "gate", "expect": ["detach-nohup", "detach-setsid", "detach-disown"]}
```

`expect` 是这条变异**必须**变红的用例名。变红在别处、或者一条都没红，都记为清单失败而不是通过。

## 3. 组件

| 文件 | 类型 | 职责 |
|---|---|---|
| `.claude/hooks/orca_channel_gate.py` | PreToolUse(Bash)，阻断 | 七条拒绝规则；记录 dispatch；同步 turn |
| `.claude/hooks/loop_wakeup_gate.py` | Stop，阻断 | 四条拒绝规则，全部基于进展 |
| `.claude/tools/coordinator_state.py` | 库 | 账本形状、turn 推导、stall 判据 |
| `.claude/tools/orca_channel.py` | 工具 | `drain` / `sweep` / `watch` / `status` / `watchdog` |
| `.claude/hooks/catalog_write_gate.py` | PreToolUse(Write/Edit)，阻断 | 拒绝手写物化产物 |
| `.claude/tools/verify_mutations.py` | 变异自测台 | 逐条反转守卫，断言指定探针变红 |
| `Scripts/rules/test_agent_harness_mutations.py` | 结构层测试 | 把上面这台机器接进 `run_verification.py` 的自动发现 |

最后一行是有意的：`.claude/` 此前不在任何验证层内，这正是它能长出一个假绿探针的原因。接入后 `verify_scripts_inventory.py` 报 211 scripts（76 test）全部可达且命名正确。

### 3.1 PreToolUse 的九条

匹配前先剥掉 heredoc 正文：正文是写进文件的数据，不是要执行的命令。

| # | 拒绝 | 实测依据 |
|---|---|---|
| 1 | detacher（`nohup` 一类） | 6 次全部零通知；96 次不带它的后台任务中位 5 秒 |
| 2 | 语句尾的 `&`（`&&`、`2>&1` 不算） | 同上，且前台的 `&` 连兜底通知都没有 |
| 3 | `orca orchestration check` 不带 `--run`／`--terminal` | 120 次里 93 次读终端默认绑定，积压 50 条含 1 条 question |
| 4 | `--peek`，以及不带 `--run` 的 `--ack` | `--peek` 不标记已读；6 份拒绝报告每 20 秒重现 1 小时。会话里 15 条不同的 `--ack` 全部没有 `--run`，acknowledge 落在终端默认绑定上 |
| 5 | `terminal create --command <agent>` 作派遣 | 产出 unsupervised dispatch，无 dispatch 记录、无 worker_done 推送 |
| 6 | `ps`/`pgrep`/`pkill` 命中 agent 或构建 token | TUI 在 agent 死后仍存活；`[x]` 自排除写法先被还原再匹配 |
| 7 | 管道之后读 `$?` | 读到的是末段退出码；按语句切分归属（`;`、换行与 `&&` 都是分隔符），`${PIPESTATUS[0]}` 放行 |
| 8 | `orca orchestration` 带 `--wait` | 整个回合被锁在一个订阅里，读不了仓库也读不了别的 Run。watch 是拿来采样的 |
| 9 | 以路径作退出条件的 `while`／`until` 循环 | 部分报告早于完成落盘；一次这样的轮询在 4 份交付里的第 1 份就宣告 worker 完成 |

外加账本规则：跨回合的 `worker-start` 在未 sweep 时被拒。

第 8、9 条与写入侧的 `catalog_write_gate.py` 来自擂台里落选的两份方案。第 8、9 条是 P1 的，第三条是 P2 的路径版本；P2 同一份里另有一条拦读取的规则，未采纳，因为读 Catalog 不改变任何绑定。

### 3.3 Write/Edit 上的一条

`Config/regression/catalog-v2.json` 与 `Config/regression/catalog-root/**` 是 `Scripts/regression/materialize_catalog_v2.py` 的产物。手写改的是字节，不是 obligation 到 summary 与 digest 的绑定，结果是一份能通过自身结构检查、却指向运行产不出的证据的 Catalog——这正是本仓库已经被咬过两次的假绿形状。规则只看路径，不读内容；读取从不拦。

### 3.2 Stop 的四条

1. loop 中的回合未武装 wakeup 且未 `stop:true` → 拒（保留原判据）。
2. 存在 `orca-run` watch 而本回合未采样它 → 拒。这是 A 与 C 的正面判据。
3. watch 报告全部 dispatch 已 settled 而本回合未 drain → 拒。
4. 本回合出现 `completed` 的 task-notification，其后除 ScheduleWakeup 外无任何工具调用 → 拒。

第 4 条是原 `IDLE_SECONDS` 的替代，**去掉了时长阈值**。见 4.1。

两组规则的开关粒度不同，因为它们防的东西不同。3.1 与 3.3 拦的是错误——进程表当完成事实、手改物化产物——不论有没有人看着都是错的，所以常开。3.2 拦的是"该继续时停下"，只在无人值守时是错误；有人在场时停下来交还控制权正是应该的。`.claude/loop-off` 只关 Stop 这一组，PreToolUse 的九条不受影响；`.claude/hooks-off` 两组全关。两个文件都不进版本控制。

## 4. 考虑过并否决的方案

### 4.1 保留并调参 `IDLE_SECONDS = 300`（否决）

原判据要求存在一条含 `completed` 的 task-notification，而它要抓的失效用 detacher 起、根本不产生通知——判据绑到了失效从不经过的通道，触发零次。把 300 调成 60 只会让它继续触发零次。

正确的修法是两步，顺序不能反：先让 detacher 在执行前被拒（通知因此必然存在），判据才第一次落在真实通道上；然后把阈值整个删掉。删掉是因为，一旦通知必然存在，"停车"的判据就是"通知到了而这一回合什么都没做"，与延迟多少秒无关。保留一个秒数只会重新引入一个先验猜测。

这不是削弱证据链约束：`IDLE_SECONDS` 从未是证据链的一部分，它是一个从未生效的节奏启发式。

### 4.2 用 hook 的 `additionalContext` 注入正确用法（否决）

这就是 `controller_background_context.py` 的形态，也是"往提示词里加一句话"的 hook 版本。已有数据：「每次醒来先跑 sweep」服从率 13/33，「无需请示」之后仍有 12 次请示。注入在协调者读到并想起时生效，而失效恰好发生在没想起的时候。本设计保留该 hook 不动（它的定位是提供实测数字，不是守卫），但没有新增任何注入型规则。

### 4.3 用 `permissionDecision: "deny"` 的 JSON 形式阻断（否决）

改用 exit 2 + stderr。JSON 字段若不被当前运行时识别，hook 会以 exit 0 结束，命令照常执行——**失败方向是放行**。本仓库已经被假绿咬过两次，一个失败即放行的守卫是第三次。exit 2 是既有 Stop hook 已经依赖的机制，失败方向是阻断。

### 4.4 用固定时长判断 worker 卡死（否决，且是硬约束）

矩阵按操作单元实时驱动，整轮时长无法先验给出。`listen.py` 的「静默 15 分钟视为死亡」在第 15 轮失效并误杀。本设计的 stalled 判据是三个连续无变化的样本；探针里有一条专门钉住 `STALE_OBSERVATIONS == 3`，因为这个探针的第一版用 `range(STALE_OBSERVATIONS)` 构造夹具，把常量同时喂给了被测方和夹具——见 5.1。

### 4.5 让 hook 直接调用 Orca 校验状态（否决）

PreToolUse 在每次 Bash 前运行，一次 `orca worker-list` 的往返会把每条命令都拖慢，且引入一个网络故障即阻断全部工作的单点。改为纯本地账本：hook 只读写 JSON，Orca 只在协调者显式调用工具时被访问。

### 4.6 用 cron 覆盖 429（部分否决，见第 6 节）

`CronCreate` 起的是一个新的 Claude 会话，它同样要过 API；配额压力下最可能同时 429。用它当唯一退路等于把恢复绑在正在故障的那条链上。改为非 LLM 的 watchdog 进程。cron 仍可作为第二层冗余，但不是本设计的主路径。

### 4.7 禁止一切后台与并发，改为全前台（否决）

会违反硬约束 4：协调者必须能同时订阅消息与查看仓库。前台化把每次等待变成阻塞，仓库那条车道就断了。探针里有 12 条 `lane-*` 用例专门证明两条车道都没被本设计挡住。

### 4.8 用 hook 校验 worker 的 diff 边界（部分否决）

散文写的写入边界被违反两次：worker 用全树 diff 抓走他人在制品，以及直接改 `catalog-v2.json` 不更新摘要。这两条都发生在 OpenCode／Claude 以 `--agent` 起的独立进程里，而 `.claude/settings.json` 只约束 Claude Code 运行时，对 OpenCode 无效——所以 hook 覆盖不了 worker 侧，第 7 节第 1 条如实登记。

第二条违反另有一个协调者侧的版本：协调者自己也会去手改物化产物。这一半 hook 能拦，就是 3.3。第一条（diff 边界）没有协调者侧版本，正确落点仍是派遣时的 worktree 隔离。

### 4.9 把 heredoc 正文一并纳入匹配（否决，被实测推翻）

第一版不剥 heredoc。它拦下的第一条命令是本文件自己的写入——DESIGN.md 引用被禁词来解释为何禁它，于是被规则 1 拒绝。剥掉正文是正确的：正文是数据不是命令。代价是"把 detacher 写进脚本、之后再执行那个脚本"看不见，列入第 7 节。两个方向各有一条变异钉住（`gate-heredoc-not-stripped`、`gate-heredoc-swallows-everything`）。

## 5. 变异自测记录

`python3 .claude/tools/verify_mutations.py`，实测 23.9 秒，39/39。流程是：先证明未变异的副本三个探针全绿（否则"变红"什么都不证明），再逐条把守卫反转，断言指定探针变红且变红在指定用例上。

```
BASELINE channel: green
BASELINE gate: green
BASELINE stop: green
PASS gate-detach: hooks/test_orca_channel_gate.py red on ['detach-disown', 'detach-nohup', 'detach-setsid']
PASS gate-heredoc-not-stripped: hooks/test_orca_channel_gate.py red on ['lane-heredoc-quoting-a-banned-word', 'lane-heredoc-then-ordinary-work']
PASS gate-heredoc-swallows-everything: hooks/test_orca_channel_gate.py red on ['heredoc-then-a-real-detacher']
PASS gate-trailing-ampersand: hooks/test_orca_channel_gate.py red on ['trailing-ampersand']
PASS gate-unbound-check: hooks/test_orca_channel_gate.py red on ['check-without-run']
PASS gate-hand-rolled-ack: hooks/test_orca_channel_gate.py red on ['hand-rolled-ack', 'peek']
PASS gate-unsupervised-dispatch: hooks/test_orca_channel_gate.py red on ['unsupervised-dispatch']
PASS gate-bracket-escape: hooks/test_orca_channel_gate.py red on ['ps-liveness']
PASS gate-process-listers: hooks/test_orca_channel_gate.py red on ['pgrep-agent', 'ps-liveness']
PASS gate-pipeline-status: hooks/test_orca_channel_gate.py red on ['pipeline-status']
PASS gate-dispatch-backlog: hooks/test_orca_channel_gate.py red on ['dispatch-next-turn-needs-sweep']
PASS gate-dispatch-not-recorded: hooks/test_orca_channel_gate.py red on ['dispatch-next-turn-needs-sweep']
PASS state-unswept-window: hooks/test_orca_channel_gate.py red on ['dispatch-next-turn-needs-sweep']
PASS state-turn-boundary: hooks/test_loop_wakeup_gate.py red on ['notification-after-arming-does-not-reset-the-turn']
PASS state-stale-threshold: tools/test_orca_channel.py red on ['the-threshold-is-a-sample-count-of-three', 'three-identical-samples-mark-a-stall']
PASS state-read-this-turn: hooks/test_loop_wakeup_gate.py red on ['open-watch-unread-this-turn-blocks']
PASS state-closed-watch: hooks/test_loop_wakeup_gate.py red on ['closed-watch-is-not-a-wait']
PASS stop-unread-watch: hooks/test_loop_wakeup_gate.py red on ['open-watch-unread-this-turn-blocks']
PASS stop-all-settled: hooks/test_loop_wakeup_gate.py red on ['all-settled-without-a-drain-blocks']
PASS stop-drain-detection: hooks/test_loop_wakeup_gate.py red on ['all-settled-after-a-sweep-passes']
PASS stop-parked-work: hooks/test_loop_wakeup_gate.py red on ['completion-then-a-short-wakeup-still-blocks', 'completion-then-only-a-wakeup-blocks']
PASS stop-unarmed-loop: hooks/test_loop_wakeup_gate.py red on ['loop-unarmed-blocks', 'previous-turn-arm-does-not-count']
PASS channel-ack-not-chained: tools/test_orca_channel.py red on ['drain-chains-each-ack-into-the-next-check']
PASS channel-question-ignored: tools/test_orca_channel.py red on ['a-report-is-archived-before-the-terminal-closes', 'an-unanswered-question-keeps-its-terminal-open']
PASS channel-report-not-archived: tools/test_orca_channel.py red on ['a-report-is-archived-before-the-terminal-closes']
PASS channel-heartbeat-kept: tools/test_orca_channel.py red on ['a-heartbeat-is-not-kept-as-a-report']
PASS channel-accepts-any-channel: tools/test_orca_channel.py red on ['a-run-is-a-channel', 'a-watch-with-no-channel-is-refused']
PASS channel-sweep-does-not-clear: tools/test_orca_channel.py red on ['a-sweep-clears-what-dispatching-recorded']
PASS watchdog-never-wakes: tools/test_orca_channel.py red on ['the-watchdog-wakes-when-every-dispatch-has-settled']
PASS watchdog-wakes-too-early: tools/test_orca_channel.py red on ['the-watchdog-does-not-wake-on-work-still-running']
mutations: 30 of 30 proven
```

### 5.0 把整个会话回放一遍

规则写完之后，把这次会话发出的 2527 条 Bash 命令逐条喂进 gate，看它到底拦什么。拦下 162 条，占 6.4%。

| 规则 | 拦下 | 判定 |
|---|---|---|
| 进程表当完成事实 | 57 | 全部真拦，`ps -o rss=` 一类不带 agent token 的放行 |
| `--ack` 不带 `--run` | 27 | 15 条不同写法，无一带 `--run` |
| `check` 不带 `--run` | 23 | 真拦 |
| detacher | 22 | 10 条不同写法，全是 `nohup` |
| `--peek` | 18 | 真拦 |
| 管道后 `$?` | 9 | 真拦 |
| `--wait` | 3 | 真拦 |
| 语句尾 `&` | 2 | 真拦 |
| `terminal create` 派遣 | 1 | 真拦 |

误拦为零。日常命令——`git diff --stat`、`ls -la`、`grep -rn`、`ps -o rss=`、`test -f`、`for` 循环——全部通行。

收窄过一次：初版把任何手写 `--ack` 一律拒绝，回放里误伤 52 条链式 ack。链式 ack 带 `--run`，是正确写法；replay 队列的是说不出自己消费了哪个 Run 的那种。改成只拦不带 `--run` 的，误拦从 53 降到 0。

写进文件的 heredoc 正文在匹配前被剥掉，所以 18 条 heredoc 形状的拦截全部来自正文之后真正执行的那条命令，不是文档里引用的禁词。

### 5.1 变异台抓到的第三个假绿

`state-stale-threshold`（把 `STALE_OBSERVATIONS` 从 3 改成 99）第一次运行时**探针保持全绿**：

```
FAIL state-stale-threshold: tools/test_orca_channel.py stayed green
mutations: 27 of 28 proven
```

原因是那条探针用 `range(ledger.STALE_OBSERVATIONS)` 构造观测列表——常量同时喂给了被测方和夹具，于是任何取值都自洽。改成字面量三个观测，并补一条 `the-threshold-is-a-sample-count-of-three` 直接钉住常量值之后变红。这与仓库既有的两次假绿（`verify_bootstrap_freeze.py` 的 `re.S` 从 `def` 匹配到文件末尾；hook 探针把 `wakeup()` 的内容块当转录记录）是同一形态：探针的形状由被测物决定，因而不构成独立证据。

### 5.2 两条车道的通行探针

`lane-repository`、`lane-repository-diff`、`lane-worker-list`、`lane-send`、`lane-watch-read`、`lane-ps-unrelated`、`lane-pipestatus`、`lane-plain-status`、`lane-logical-and`、`lane-redirect`、`lane-heredoc-quoting-a-banned-word`、`lane-heredoc-then-ordinary-work` 全部断言 exit 0。硬约束 4 要求订阅与查看仓库都不被阻塞，这十二条是它的探针。

### 5.3 上线后的两次真实拦截

守卫注册后本会话撞上它两次，两次拦的都是我自己。

第一次是规则 7：

```
PreToolUse:Bash hook error: `$?` after a pipeline is the last stage's exit code,
not the command's: `python3 Scripts/rules/verify_scripts_inventory.py 2>&1 | tail -5`.
Read ${PIPESTATUS[0]}, or drop the pipe and inspect the captured output separately.
```

这正是审计里记的 16 处形态之一。改成 `> /tmp/inv.txt 2>&1; echo "exit=${?}"` 后通过，读到真实退出码 0。

第二次是规则 1 误伤本文件自身的写入——见 4.9，规则因此收窄。

## 6. 429 那个洞

**它在 hook 层结构上够不到，这是确定的。** hook 挂在回合生命周期上：PreToolUse 需要有工具调用发生，Stop 需要回合结束。429 使回合根本没执行，两个事件都不产生。任何写在 `.claude/hooks/` 里的东西都覆盖不了它，会话死 39 分钟的那次没有任何 hook 可以介入。

因此恢复必须来自**不是回合的东西**。本设计的覆盖是 `orca_channel.py watchdog`：`watch open --wake-command <cmd>` 时以 `start_new_session=True` 拉起一个不含 LLM 的轮询进程，PID 记在 `.claude/state/watchdog.pid`。它的唯一判据在 `wake_reason()`：某个 watch 的 channel 报告全部 dispatch 已 settled，而账本显示协调者的最后一次观测早于这次变化——通道说完了、协调者没看见。此时执行 wake command（默认形态是一条 `orca orchestration send`，因为一条入站 Orca 消息本身就是推进会话的输入事件），并把 `reason` 记进 `wakes`。

这里必须说清一件事：**我禁掉了 detacher，然后自己起了一个 detached 进程。** 二者方向相反。被禁的那种是用脱离进程去*替代*推送通道，结果是通知消失；watchdog 是用脱离进程去*恢复*推送通道，它自己不产出工作，只在通道已经完成而无人接收时把事件重新送进会话。它是整套设计中唯一一个 detached 进程，由唯一一条受管路径创建。

三条正向断言加两条变异钉住它的判据：`the-watchdog-wakes-when-every-dispatch-has-settled`、`the-watchdog-stays-quiet-once-the-coordinator-has-seen-it`、`the-watchdog-does-not-wake-on-work-still-running`，以及 `watchdog-never-wakes`、`watchdog-wakes-too-early`。

**退路与降级是可见的**：`--wake-command` 未给出时 watchdog 不启动，`watch open` 打印 `watchdog: not started: no --wake-command`；`orca_channel.py status` 每次都报 `watchdog: pid N` 或 `not running`。所以"没有出站唤醒"是一个被打印出来的状态，而不是一个沉默的假设。若 watchdog 也没起，会话退回到 429 之前的行为——即人类介入，与现状相同，没有变差。

## 7. 未覆盖的部分

1. **worker 侧的写入边界。** 3.3 的路径守卫只对 Claude Code 运行时生效；同一个手改物化产物的动作，OpenCode worker 做时无人阻拦，全树 diff 抓走他人在制品同样如此。正确的落点是派遣时的 worktree 隔离与 `git apply` 前的重叠检查（`apply_edits.py` 已有 overlap 检测），不是 hook。**未实现。**

2. **detacher 写进脚本、之后再执行那个脚本。** 4.9 收窄规则 1 的代价：heredoc 正文不参与匹配，因此写入的那一步看不见，而后续的 `bash script.sh` 命令文本里也没有被禁词。未做脚本内容的二次扫描。

3. **watchdog 自身的存活。** 它被 kill、机器重启、或异常退出，都会让 429 的覆盖消失。`status` 会报 `not running`，但没有任何东西强制协调者去看 `status`。二层守卫（例如让 `watch read` 在 watchdog 不在时重启它）没有实现。

4. **`.claude/hooks-off` 是一个真实的旁路。** 存在即全部规则关闭（`.claude/loop-off` 只关 Stop 一组）。设计上它必须存在（守卫误伤时需要出口），`status` 会把它打印成 `gate: OFF`，但没有任何机制阻止协调者创建它并忘记删除。

5. **同一 worktree 并发多个协调者会话。** 账本按 `session` 键，新 session 会重置整份。两个会话交替写会互相清空对方的 watch 与 dispatch 记录。当前拓扑是一 worktree 一协调者，未支持并发。

6. **`--peek` 被整条禁掉，包括只读查看。** 队列只有一个消费者这条约束比"允许只读 peek"更重要——已有的复发证明两者难以在命令文本上区分（`LAST=$(check --peek …)` 与随后的 `--ack "$LAST"` 可以在同一条 Bash 调用里，也可以跨调用）。想只读查看时用 `worker-list --run`，它不触碰队列。带 `--run` 的手写 `--ack` 则是放行的：回放证明它是正确写法，规则只认那个说不出 Run 的形状。

7. **`orca_channel.py` 的 Orca 交互只在 FakeOrca 下被证明。** 探针驱动的是注入的 `runner`，没有对真实 Orca runtime 跑过。真实往返的字段名（`deliveryId`、`dispatchStatus`、`agentTerminalHandle`、`ptyKilled`）沿用 `sweep.py`／`run_workers.py` 已在 41 小时会话中实际跑通的形状，但本次未复验。

8. **cron 作为第二层未实现。** 4.6 论证了它不该是主路径，但它可以作为 watchdog 之外的独立冗余；本次没有引入 `CronCreate` 的用法约定。
