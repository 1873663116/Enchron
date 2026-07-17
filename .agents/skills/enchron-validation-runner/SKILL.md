---
name: enchron-validation-runner
description: 仅供 Enchron 验证线程使用，在主控批准后认领唯一的本地 Apple 重型验证槽位，记录进程与证据，并把完成、阻塞或复核请求交还主控。
---

# Enchron 验证执行

仅由 `validation-worker` 读取。缺陷处理线程与主控不使用本 skill。

## 执行一项任务

收到主控的明确启动消息后，先运行 `python3 script/validation_queue.py claim --worker <worker-id>`。只有命令返回本任务时，才能启动 `swift test`、`xcodebuild`、macOS App、Simulator、UI/E2E、Instruments 或 RealityKit 验证。

在队列工具外启动验证命令，随即以 `record-process TASK --pid PID --command ...` 登记 PID。保存 revision、工作树、精确命令、目标/测试夹具、首个失败边界与证据产物路径。

进程退出并保存证据后，以 `complete TASK --outcome passed|failed|cancelled --evidence PATH` 结束。已登记 PID 存活时，`complete` 会拒绝释放槽位。

## 升级

Review Deadline、进程缺失或外部阻塞时，保持槽位，使用 `escalate` 或 `block`，并向主控报告任务 ID、状态、证据路径、首个失败边界与所需裁决。不得自行杀进程、释放槽位或启动下一项任务。
