# Enchron Entropy Automation Workflow

本文件定义 Enchron 的自动化熵治理系统如何工作。它描述的是完整系统的职责分工和阶段协议，不是某一个 Agent 的提示词。

这套系统面向个人开源项目场景设计：仓库在 GitHub 上公开，自动化需要持续清理仓库，但不应直接改写主线。默认策略是：

专用 worktree -> cleaner agent -> 完成任务 -> 验证 -> commit -> push -> PR -> reviewer agent ->  merge? y/n `

## 核心原则

- 自动化修复必须能回到主线，否则没有长期价值
- 自动化修复进入主线前，默认经过 PR，而不是直接 merge
- `worktree` 是隔离施工现场，不是并线机制
- `branch` 是自动化修复的历史线
- `PR` 是自动化修复申请进入主线的正式入口
- reviewer agent 审的是 PR，不是 worktree 本身
- 外部调度系统负责运行时机、worktree 生命周期和合并后的同步策略；仓库文档负责行为约束和输出规范
- 对 cleaner agent 来说，`worktree -> branch -> PR` 必须是一条连续、可机械执行的链路，而不是运行时临场判断的拼装流程
- 对 reviewer agent 来说，默认执行环境应是主仓库 `main`，而不是另开 reviewer worktree
- GitHub PR body、review comment、issue comment 是 cleaner 和 reviewer 之间的主公共状态源；仓库内不默认维护并行 live log

## Branch / PR 契约

为了让 cleaner agent 能稳定自动运行，外部调度器与 cleaner agent 之间需要一份明确契约：

- 调度器应优先创建“已绑定自动化分支”的专用 worktree，而不是让 agent 自己从 detached HEAD 起步
- 一个自动化分支只承载一个 cleaner theme
- 一个 open PR 只对应一个自动化分支和一个 cleaner theme
- 同主题的后续增量修复应继续复用原分支和原 PR
- 新主题必须创建新分支和新 PR
- automation memory 路径应在消息中提供可直接写入的绝对路径；如果使用环境变量写法，调度器必须保证变量已展开或在运行环境中存在

推荐命名：

- branch: `automation-<cleaner-theme>`
- PR title: `chore(entropy): <cleaner theme>`

## Shared State 契约

为了让 nightly cleaner 与 reviewer 在不恢复旧会话的前提下稳定接力，公共状态约定如下：

- 当前 cleaner 主题的真实状态以 GitHub PR 为准，而不是某个本地终端会话
- cleaner 必须在 PR body 中维护本轮清理主题、验证结果和 deferred issues
- reviewer 若给出 `request_changes` 或 `needs_human_validation`，必须把结构化结论写入 PR comment 或 review comment
- cleaner 返工时，必须先读取当前 open PR 的 body 与最近的 reviewer 结构化评论，再决定是否继续原分支
- automation memory 仅作为各自动化的私有短记忆，不作为 cleaner / reviewer 之间的共享事实来源
- 若未来确实需要长期审计，可追加归档日志，但它不应先于 GitHub PR 成为主状态源

## 参与者与职责

### cleaner Agent

cleaner agent 负责：

- 读取仓库文档和自动化文档
- 在本轮运行预算内选择一个清理主题
- 在同一主题下连续处理一组兼容问题
- 运行验证
- 在验证通过时 commit、push、创建或更新 PR
- 在发现当前 worktree 处于 detached HEAD 时，切换到自动化分支后再继续

cleaner agent 不负责：

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
- 在不通过时，把结构化返工意见写回当前 PR
- 在通过并可安全合并时，直接 merge，并把主仓库 `main` fast-forward 到最新

reviewer agent 不负责：

- 直接修复代码
- 替 cleaner agent 做实现决策
- 依赖 detached worktree 状态来完成 merge


## 推荐执行模型

### Phase 1: cleaner Run

cleaner agent 在该 worktree 中运行，并读取(如已读取，忽略)：

- `workspace-agents/automation/entropy-governance-agent.md`
- `AGENTS.md`
- `ARCHITRCTURE.md`
- `TESTING.md`
- `REGRESSION.md`
- `PLANS.md`
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
- 若当前 worktree 处于 detached HEAD，cleaner agent 应先创建并切换到自动化分支，再开始提交路径上的工作
- 若当前状态既不是自动化分支，也不能安全创建自动化分支，则退出并报告，不要继续在不合法状态下工作

### Phase 2: Validation Gate

cleaner agent 在允许提交前必须完成：

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

cleaner agent 在 PR 中必须附带：

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

- 若当前自动化分支已有 open PR，cleaner agent 应更新该 PR，而不是再建一个新 PR
- 若当前自动化分支没有 open PR，cleaner agent 应创建新 PR
- 不允许把不同 cleaner theme 的提交叠加到同一个 open PR 中
- 不允许因为“本轮已经跑过”就强行创建空 PR 或低价值 PR

PR body 推荐固定模板：

- `## Findings`
- `## Selected Issue`
- `## Changes Made`
- `## Verification`
- `## Deferred Issues`
- `## PR Summary`

cleaner 在复用既有 PR 返工时，推荐追加一条结构化 comment：

- `## Addressed Findings`
- `## Changes Since Review`
- `## Re-Verification`
- `## Remaining Gaps`

### Phase 4: Review Run

reviewer agent 是一个独立任务。它可以在 PR 创建后、PR 更新后、或定时轮询 open PR 时运行。

reviewer 默认应在主仓库 `main` 中运行。推荐顺序：

1. `git pull --ff-only origin main`
2. 查找当前 open entropy PR
3. 读取 PR body、最新 diff、最新 reviewer / cleaner 结构化评论
4. 必要时做最小本地复核
5. 产出 `approve` / `request_changes` / `needs_human_validation`
6. 若 `approve` 且可安全合并，则 merge PR
7. merge 后再次 `git pull --ff-only origin main`

reviewer agent 读取：

- `workspace-agents/automation/pr-review-agent.md`
- `AGENTS.md`
- `ARCHITRCTURE.md`
- `TESTING.md`
- `REGRESSION.md`
- `PLANS.md`
- `AGENTS.md`
- `ARCHITECTURE.md`
- `REGRESSION.md`
- `TESTING.md`
- `workspace-agents/quality_gates.md`

然后对当前自动化 PR 给出审阅结论。如果是 `request_changes` 或 `needs_human_validation`，必须把结构化意见写回 PR；如果是 `approve`，可以直接 merge，然后再拉取到本地 main 中。
默认不需要人类参与，只有失败和难以判断的问题才通知人类。

reviewer comment 推荐固定模板：

- `## Review Decision`
- `## Blocking Findings`
- `## Required Rework`
- `## Verification Gaps`
- `## Next Action`

其中：

- `Review Decision` 只能是 `approve` / `request_changes` / `needs_human_validation`
- `Blocking Findings` 在无阻塞问题时写“未发现需要阻止合入的问题”
- `Required Rework` 只写 cleaner 下一轮必须完成的动作
- `Verification Gaps` 只写仍未被自动化证明的风险
- `Next Action` 明确写“merge now”或“cleaner revise on same PR”


## 失败处理

如果 cleaner 运行失败，应保留：

- 原始主题或候选问题
- 当前 diff
- 失败命令和退出状态
- 已完成验证项
- 未完成原因

如果 review 运行失败，应保留：

- 待审 PR 标识
- 已读取的验证信息
- 无法完成审查的原因
- 若已写入部分 reviewer comment，应说明该 comment 是否代表最终结论

如果 post-merge sync 被跳过，应保留：

- 已合并 PR 标识
- 主工作区当前分支
- 主工作区是否干净
- 跳过同步的原因

不要在失败后无边界扩大修改范围，也不要为了“有产出”而强行提交。
