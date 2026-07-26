# Enchron 本地验证队列

本文是跨任务共享 Apple 重型验证槽位的唯一操作协议。`verification-system.md` 定义什么证据构成产品验证；本文只定义任务如何提交、认领、执行、复核和释放槽位。

队列是事实账本和原子租约，不是消息系统。`Scripts/verification/validation_queue.py` 只记录状态；它不会创建或唤醒任务，也不会启动、中断或终止验证进程。数据库默认位于 Git common directory 的 `enchron-validation.sqlite3`，因此同一仓库的 Worktree 共享唯一槽位；`--db` 或 `ENCHRON_VALIDATION_DB` 可以显式指定其他位置。

## 职责

### 普通任务：submit-only

实现、缺陷处理和调查任务可以提交验证需求，不能认领槽位或启动 `swift test`、`xcodebuild`、macOS App、Simulator、UI/E2E、Instruments、RealityKit 等本地 Apple 重型验证。

提交前固定当前 Git revision、工作树、拟执行的精确命令、验证目标和首个验收边界，然后运行：

```sh
python3 Scripts/verification/validation_queue.py --json submit TASK_ID \
  --summary "SUMMARY" \
  --worktree /absolute/worktree \
  --requested-by WORKER_ID \
  --command "COMMAND" \
  --review-after-minutes 45
```

`TASK_ID` 必须唯一；队列会把工作树解析为绝对路径。工具不保存 Git revision，因此提交者必须把 revision 与任务 ID 一并报告给 Orchestrator。`--kind` 只在默认的 `apple-heavy-validation` 不足以描述任务时使用。

提交完成的判据是 Orchestrator 已收到任务 ID、revision、工作树、目标、精确命令和首个验收边界。提交者随后等待结果，不自行执行该验证。

### Orchestrator：观察、唤醒和裁决

只有显式调用通用 Orchestrator 的任务负责队列调度。它使用以下命令读取事实：

```sh
python3 Scripts/verification/validation_queue.py --json status
```

当没有 active task，且队首任务已获准执行时，Orchestrator 才唤醒唯一的 Validation Task，并发送任务 ID、revision、工作树、验证目标和精确命令。`claim` 总是按 `submitted_at, task_id` 认领最早的 queued task，不能指定任务 ID；Orchestrator 因此必须先确认队首就是要执行的任务。

存在 `running`、`attention_required` 或 `blocked` 任务时，槽位仍被占用，Orchestrator 不唤醒后续任务。Review Deadline、已登记 PID 消失、验证失败和外部阻塞都只触发裁决：继续或恢复、明确停止、补充证据或重新分派。时间经过本身不授权终止进程、完成任务或释放槽位。

### Validation Task：claimed-task-only

Validation Task 必须由 Orchestrator 明确委派。收到启动消息后运行：

```sh
python3 Scripts/verification/validation_queue.py --json claim --worker WORKER_ID
```

只有返回的任务 ID 与委派任务一致时，才能在返回的工作树和委派指定的 revision 上启动验证。若 ID 不一致，对实际认领的任务运行 `escalate` 并立即报告 Orchestrator；保持槽位，不执行错误任务或继续认领。

验证进程启动后立即登记实际 PID 和精确命令：

```sh
python3 Scripts/verification/validation_queue.py --json record-process TASK_ID \
  --pid PID \
  --command "COMMAND"
```

保存 `verification-system.md` 要求的环境、fixture、节点、控制矩阵、首个失败边界以及日志、`.xcresult` 和机器产物。Validation Task 每次只执行已认领的一项任务；除非 Orchestrator 另行委派狭窄修复，否则不修改产品代码。

进程退出且证据落盘后结束任务：

```sh
python3 Scripts/verification/validation_queue.py --json complete TASK_ID \
  --outcome passed \
  --evidence /absolute/evidence/path
```

`--outcome` 只能是 `passed`、`failed` 或 `cancelled`。已登记 PID 仍存活时，`complete` 会拒绝释放槽位；Validation Task 需要把事实交给 Orchestrator 裁决。

## 阻塞、复核和恢复

需要主控判断但验证尚未形成外部阻塞时：

```sh
python3 Scripts/verification/validation_queue.py --json escalate TASK_ID --reason "REASON"
```

外部条件阻止继续时：

```sh
python3 Scripts/verification/validation_queue.py --json block TASK_ID --reason "REASON"
```

两者都保持槽位。Orchestrator 决定恢复后运行：

```sh
python3 Scripts/verification/validation_queue.py --json resume TASK_ID --reason "REASON"
```

`resume` 把任务恢复为 `running`，并从恢复时重新计算 Review Deadline。Review Deadline 到期只会让 `status` 返回 `review_due` 和通知；任务状态与槽位不会自动改变。PID 未登记表示进程缺少可观察事实，Validation Task 应升级；已登记 PID 不再存活时，`status` 会要求 Orchestrator 复核，但仍保留槽位。

## 返回证据

Validation Task 在完成、阻塞或升级时向 Orchestrator 返回：任务 ID、Git revision、工作树、队列状态或 outcome、精确命令、目标与 fixture、首个失败边界、证据路径以及需要的裁决。Orchestrator 依据当前 revision 的证据决定是否集成；队列中的 terminal state 只表示槽位已释放，不替代 `verification-system.md` 的产品通过条件。
