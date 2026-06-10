# Issue tracker

Issues for this repo live in **GitHub Issues** (`github.com/1873663116/XrPlayer`).

## How agents interact with it

Use the `gh` CLI:

- **Create an issue:** `gh issue create --title "..." --body "..." --label "..."`
- **List open issues:** `gh issue list`
- **List by label:** `gh issue list --label "needs-triage"`
- **View an issue:** `gh issue view <number>`
- **Comment:** `gh issue comment <number> --body "..."`
- **Close:** `gh issue close <number>`
- **Apply/remove labels:** `gh issue edit <number> --add-label "..." --remove-label "..."`

Cloud agent sessions do not have `gh`; use the GitHub MCP tools (`mcp__github__*`) instead.

## Conventions

- Always set a clear, action-oriented title.
- Use labels to drive triage state (see `triage-labels.md`).
- 一个可执行工作单元 = 一个 issue；动工前 body 写明验收条件，不满足不关单。
- 证据原件（截图/日志/`nm` 输出/录屏）贴 issue 评论；仓库不进二进制证据。
- PR 描述必带 `Closes #N`（合入默认分支自动关单）。
- 关闭三选一并留一句结语：completed（附证据/PR 链接）/ not planned（为什么不做）/ duplicate（指向正主）。
- `ready-for-agent` 只给前置已满足、AFK 可执行的 issue；串行任务的后续项不预先升标，由每轮收尾清扫升。
- 每轮收尾做 issue 卫生：该关的关、过期 `needs-triage` 重分诊。open 列表超一屏（约 25）是水位警报——呈报人类裁决要不要收口；agent 不为凑数关单，没有证据或人类裁决支撑的关闭比堆积更糟。
- issue 是讨论现场不是档案馆：边界决定回流 ADR / `CONTEXT.md`，可迁移经验回流 `docs/solutions/`。
