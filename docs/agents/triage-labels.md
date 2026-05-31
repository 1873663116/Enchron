# Triage labels

The `triage` skill moves issues through a state machine using these labels.

| Role | Label string | Meaning |
|------|--------------|---------|
| Needs triage | `needs-triage` | Maintainer needs to evaluate |
| Needs info | `needs-info` | Waiting on reporter |
| Ready for agent | `ready-for-agent` | Fully specified, AFK-ready |
| Ready for human | `ready-for-human` | Needs human implementation |
| Won't fix | `wontfix` | Will not be actioned |

## Notes

- These are the canonical role → label mappings. If you rename a label here, update it everywhere the `triage` skill is invoked.
- The skill applies these labels via the issue tracker's CLI (see `issue-tracker.md`).
