# OMC -> Codex Migration Plan

## Scope

1. Skill-level migration (completed)
2. Runtime orchestration migration (in progress)
3. Hook/event integration migration (pending adapter)

## Compatibility mapping

- OMC skill markdown -> Codex skill markdown: mostly compatible
- OMC tmux orchestration -> Codex parallel tool calls: partially compatible
- OMC plugin hooks -> Codex native lifecycle hooks: not 1:1, adapter required

## Proposed adapter layer

- Create a thin command router script
- Map OMC mode commands to Codex equivalents
- Keep skill invocation deterministic and auditable

## Subagent capability in Codex

Codex can execute task decomposition and parallel operations (tool parallelism), which covers most practical "sub-agent" workflows for engineering tasks.

## Next milestones

- M1: command router MVP
- M2: hook emulation for key workflows (plan/review/team)
- M3: telemetry and trace output compatible with OMC expectations
