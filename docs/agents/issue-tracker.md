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

## Conventions

- Always set a clear, action-oriented title.
- Use labels to drive triage state (see `triage-labels.md`).
- When an issue is fully specified and AFK-ready, label it `ready-for-agent`.
