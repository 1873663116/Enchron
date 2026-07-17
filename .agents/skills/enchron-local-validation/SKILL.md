---
name: enchron-local-validation
description: 协调 Enchron 并行缺陷工作与唯一的本地 Apple 重型验证槽位。提交、认领、观察、升级或裁决共享 Mac 上的 swift test、xcodebuild、macOS App、Simulator、UI/E2E、Instruments 或 RealityKit 验证时使用。
---

# Enchron 本地验证编排

从任一 Enchron 工作树运行 `script/validation_queue.py`。SQLite 数据库默认位于仓库共享 Git 公共目录；只有所有参与工作树都必须使用另一个明确共享的数据库时，才设置 `ENCHRON_VALIDATION_DB`。

## 角色

- `controller`（主控）：与用户对话、分配工作树、解决冲突、接收升级，并决定继续、停止或集成。
- `bug-worker`（缺陷处理线程）：只诊断和修改被分配的文件。可运行不触发 Apple 重型构建的静态检查；提交验证，但不得认领或运行共享验证槽位。
- `validation-worker`（验证线程）：唯一能认领槽位的线程；每次只运行一条 Apple 重型验证命令。启动后记录 PID，并以证据结束任务。

在每个委派提示中显式声明角色，绝不能从线程名推断。委派 envelope 必须包含 `role`、`controller_thread_id`、`task_id`、`worktree` 与 `validation_policy`。

## 提交与执行

采用以下流程：

```sh
python3 script/validation_queue.py submit local-playback-e2e \
  --summary 'Local file playback regression E2E' \
  --worktree "$PWD" \
  --requested-by bug-worker-local-playback \
  --kind macos-e2e \
  --review-after-minutes 45

python3 script/validation_queue.py claim --worker validation-worker-1
# 在队列工具外启动命令，再登记其 PID。
python3 script/validation_queue.py record-process local-playback-e2e --pid "$PID" --command 'xcodebuild ...'
python3 script/validation_queue.py complete local-playback-e2e --outcome passed --evidence /absolute/path/to/result.md
```

将 `swift test`、`xcodebuild`、macOS App 启动、Simulator、UI/E2E 自动化、Instruments 与 RealityKit 运行视为 Apple 重型验证。未认领槽位前不得启动其中任何一项。

## 复核时点（Review Deadline）与阻塞

Review Deadline 是信号，不是超时。`status --json` 会报告 `review_due` 与 `controller_attention_required`；它不会改变状态、中断进程或释放槽位。

需要主控裁决时使用 `escalate TASK --reason ...`；遇到外部依赖时使用 `block TASK --reason ...`。两种状态都会保留槽位。只有在主控裁决后才能使用 `resume TASK` 或以 `complete` 结束。已登记 PID 仍存活时，`complete` 会拒绝释放槽位。

向主控发送任务 ID、当前状态、首个失败边界、证据路径及所需裁决。无法联系主控时，保持任务在 `attention_required` 或 `blocked`；不得自行释放。

## 证据与集成

记录精确 revision、工作树、命令、目标/测试夹具、首个失败边界与证据产物路径。构建或测试结果不能替代 Enchron 验收系统要求的产品 E2E 层。验证完成后，由主控决定集成与冲突解决。
