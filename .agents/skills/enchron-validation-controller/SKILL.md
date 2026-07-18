---
name: enchron-validation-controller
description: 仅供 Enchron 主控使用，用于拆分并行缺陷任务、编写最小委派提示、观察本地验证队列、唤醒唯一验证线程并裁决阻塞或复核时点。
---

# Enchron 主控编排

仅由直接与用户对话、负责工作树和集成决策的主控读取。缺陷处理线程与验证线程不使用本 skill。

## 模型路由

默认使用 Terra，effort 为 high。Luna、Terra、Sol 的智能程度依次递增；根据问题的复杂性与不确定性选择模型。effort 根据执行步骤、推理深度和收敛难度动态调整：较低 effort 收敛更快、思考预算更少，较高 effort 允许更充分的检查、推理和尝试。这些是动态路由参考，不是机械规则。禁止使用 Sol Ultra。

## 委派

先划分互不重叠的文件所有权和验收边界，再创建工作树与任务。委派提示只提供子线程不知道、且完成任务必要的事实：

```text
role: bug-worker | validation-worker
task_id: ...
worktree: ...
ownership: 文件或模块范围
goal: 症状、已有证据与完成条件
validation_policy: submit-only | claimed-task-only
return: 根因/改动/轻量检查/证据路径或所需裁决
```

不要重复 AGENTS.md、skill、MCP、工具清单、通用 Git 规则或已由角色定义承载的约束。不要把多个不相干的 bug 放入同一个任务。

## 队列调度

队列是事实账本，不是消息系统。运行 `python3 script/validation_queue.py --json status` 后由主控裁决；它不会自行唤醒任何线程。

缺陷处理线程提交验证后，应向主控报告任务 ID、revision、首个验收边界与所需命令。验证线程完成、阻塞或升级后，也应向主控报告相同的最小事实。

若没有 active task 且主控批准下一项验证，向唯一验证线程发送一条短消息：任务 ID、工作树/revision、验收目标，以及“先 `claim`，成功后才运行”。验证线程自行认领，避免主控替它占用槽位。若有 active task，不发送启动消息给后续任务。

## 裁决

Review Deadline、PID 缺失、失败或外部阻塞只要求主控判断继续、恢复、停止或重新分派。绝不把时间阈值视为杀进程或释放槽位的授权。主控在证据充分后决定集成与冲突解决。
