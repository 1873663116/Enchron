# Enchron Entropy Automation Workflow

本文件定义 Enchron 的自动化熵治理系统如何工作。它描述的是完整系统的职责分工和阶段协议，不是某一个 Agent 的提示词。

这套系统面向个人开源项目场景设计：仓库在 GitHub 上公开，自动化需要持续清理仓库，但不应直接改写主线。默认策略是：

`外部调度 -> 专用 worktree -> cleanup agent -> 验证 -> commit -> push -> PR -> reviewer agent ->  merge? y/n `

## 核心原则

- 自动化修复必须能回到主线，否则没有长期价值
- 自动化修复进入主线前，默认经过 PR，而不是直接 merge
- `worktree` 是隔离施工现场，不是并线机制
- `branch` 是自动化修复的历史线
- `PR` 是自动化修复申请进入主线的正式入口
- reviewer agent 审的是 PR，不是 worktree 本身
- 外部调度系统负责运行时机、worktree 生命周期和合并后的同步策略；仓库文档负责行为约束和输出规范
- 对 cleanup agent 来说，`worktree -> branch -> PR` 必须是一条连续、可机械执行的链路，而不是运行时临场判断的拼装流程

## Branch / PR 契约

为了让 cleanup agent 能稳定自动运行，外部调度器与 cleanup agent 之间需要一份明确契约：

- 调度器应优先创建“已绑定自动化分支”的专用 worktree，而不是让 agent 自己从 detached HEAD 起步
- 一个自动化分支只承载一个 cleanup theme
- 一个 open PR 只对应一个自动化分支和一个 cleanup theme
- 同主题的后续增量修复应继续复用原分支和原 PR
- 新主题必须创建新分支和新 PR
- automation memory 路径应在消息中提供可直接写入的绝对路径；如果使用环境变量写法，调度器必须保证变量已展开或在运行环境中存在

推荐命名：

- branch: `automation/<automation-id>-<cleanup-theme>`
- PR title: `chore(entropy): <cleanup theme>`

## 参与者与职责

### Cleanup Agent

cleanup agent 负责：

- 读取仓库文档和自动化文档
- 在本轮运行预算内选择一个清理主题
- 在同一主题下连续处理一组兼容问题
- 运行验证
- 在验证通过时 commit、push、创建或更新 PR
- 在发现当前 worktree 处于 detached HEAD 时，切换到自动化分支后再继续

cleanup agent 不负责：

- 创建主工作区
- 决定是否直接 merge 主线
- 审核自己的 PR
- 在多个无关主题之间做“顺手一起修”的打包决策

### Reviewer Agent

reviewer agent 负责：

- 读取 reviewer 文档和项目约束文档
- 审查当前自动化 PR 是否应进入主线
- 判断 PR 是否真的降低了漂移和复杂度
- 判断 PR 是否破坏架构边界或伪造验证
- 给出 `approve`、`request_changes` 或 `needs_human_validation`

reviewer agent 不负责：

- 直接修复代码
- 替 cleanup agent 做实现决策


## 推荐执行模型

### Phase 1: Cleanup Run

cleanup agent 在该 worktree 中运行，并读取：

- `workspace-agents/automation/entropy-governance-agent.md`
- `workspace-agents/automation/entropy-automation-workflow.md`
- `AGENTS.md`
- `ARCHITECTURE.md`
- `REGRESSION.md`
- `TESTING.md`

本轮运行目标：

- 选择一个清理主题
- 在该主题下修若干兼容问题
- 完成验证
- 如无有效改动或验证失败，则退出且不提交

进入 Phase 1 后，先做分支前提检查：

- 若当前 worktree 已绑定自动化分支，直接继续
- 若当前 worktree 处于 detached HEAD，cleanup agent 应先创建并切换到自动化分支，再开始提交路径上的工作
- 若当前状态既不是自动化分支，也不能安全创建自动化分支，则退出并报告，不要继续在不合法状态下工作

### Phase 2: Validation Gate

cleanup agent 在允许提交前必须完成：

- `swift build`
- `swift test`
- `swiftlint lint`
- `scripts/check-workaround.sh XrPlayer/`
- `git diff --name-only`
- `REGRESSION.md` 回归项映射

如果验证失败：

- 不 commit
- 不 push
- 不发 PR
- 总结失败原因。尝试将问题修复。继续验证,直至通过
- 不得为了通过而临时扩大到新的清理主题

如果验证通过且改动值得保留：

- 允许 commit
- 允许 push
- 允许创建或更新 PR

如果没有有效 diff：

- 不 commit
- 不 push
- 不发 PR
- 记录“无高置信度可提交改动”并结束本轮运行

### Phase 3: PR Publication

cleanup agent 在 PR 中必须附带：

- `## Findings`
- `## Selected Issue`
- `## Changes Made`
- `## Verification`
- `## Deferred Issues`
- `## PR Summary`

PR 的目标不是“越小越好”，而是：

- 单一清理主题
- 边界清晰
- 理由充分
- 验证可信
- 审阅成本可控

PR 发布规则：

- 若当前自动化分支已有 open PR，cleanup agent 应更新该 PR，而不是再建一个新 PR
- 若当前自动化分支没有 open PR，cleanup agent 应创建新 PR
- 不允许把不同 cleanup theme 的提交叠加到同一个 open PR 中
- 不允许因为“本轮已经跑过”就强行创建空 PR 或低价值 PR

### Phase 4: Review Run

reviewer agent 是一个独立任务。它可以在 PR 创建后、PR 更新后、或定时轮询 open PR 时运行。

reviewer agent 读取：

- `workspace-agents/automation/pr-review-agent.md`
- `workspace-agents/automation/entropy-automation-workflow.md`
- `AGENTS.md`
- `ARCHITECTURE.md`
- `REGRESSION.md`
- `TESTING.md`
- `workspace-agents/quality_gates.md`

然后对当前自动化 PR 给出审阅结论，如果通过，可以直接 merge，然后再拉取到本地main中。
默认不需要人类参与，只有失败和难以判断的问题才通知人类。


## 失败处理

如果 cleanup 运行失败，应保留：

- 原始主题或候选问题
- 当前 diff
- 失败命令和退出状态
- 已完成验证项
- 未完成原因

如果 review 运行失败，应保留：

- 待审 PR 标识
- 已读取的验证信息
- 无法完成审查的原因

如果 post-merge sync 被跳过，应保留：

- 已合并 PR 标识
- 主工作区当前分支
- 主工作区是否干净
- 跳过同步的原因

不要在失败后无边界扩大修改范围，也不要为了“有产出”而强行提交。
