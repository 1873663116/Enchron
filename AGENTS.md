# Repository Agent Rules

## Default Git Workflow

- After finishing an implementation task and verifying it passes relevant checks, the agent should automatically:
  - create a commit with a clear message
  - push the current branch to `origin`

- If push is blocked (for example network/auth failure), the agent must report the exact blocker and the next manual command.

