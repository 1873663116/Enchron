---
name: enchron-local-validation
description: Coordinate concurrent Enchron bug work with one local Apple-heavy validation slot. Use when submitting, claiming, observing, escalating, or adjudicating swift test, xcodebuild, macOS App, Simulator, UI/E2E, Instruments, or RealityKit validation on the shared Mac.
---

# Enchron Local Validation

Use `script/validation_queue.py` from an Enchron worktree. The SQLite database defaults to the repository's shared Git common directory; set `ENCHRON_VALIDATION_DB` only when every participating worktree must use a different explicitly shared database.

## Roles

- `controller`: talks to the user, assigns worktrees, resolves conflicts, receives escalations, and decides whether work continues, stops, or is integrated.
- `bug-worker`: diagnoses and edits only its assigned files. Run static checks that do not invoke Apple-heavy builds. Submit validation; do not claim or run the shared validation slot.
- `validation-worker`: the sole worker that claims the slot and runs one Apple-heavy validation command at a time. Record its PID after launch and finish with evidence.

Declare the role in each delegated prompt; never infer it from a thread name. Include `role`, `controller_thread_id`, `task_id`, `worktree`, and `validation_policy` in the delegation envelope.

## Submit and run

Use this flow:

```sh
python3 script/validation_queue.py submit local-playback-e2e \
  --summary 'Local file playback regression E2E' \
  --worktree "$PWD" \
  --requested-by bug-worker-local-playback \
  --kind macos-e2e \
  --review-after-minutes 45

python3 script/validation_queue.py claim --worker validation-worker-1
# Start the command outside the queue tool, then record its PID.
python3 script/validation_queue.py record-process local-playback-e2e --pid "$PID" --command 'xcodebuild ...'
python3 script/validation_queue.py complete local-playback-e2e --outcome passed --evidence /absolute/path/to/result.md
```

Treat `swift test`, `xcodebuild`, a macOS App launch, Simulator, UI/E2E automation, Instruments, and RealityKit runs as Apple-heavy. Do not start any of them without a claimed slot.

## Review deadlines and blocks

A review deadline is a signal, not a timeout. `status --json` reports `review_due` and `controller_attention_required`; it does not change state, interrupt a process, or release the slot.

Use `escalate TASK --reason ...` for a review needed from the controller, and `block TASK --reason ...` for an external dependency. Both states retain the slot. Only after controller judgment use `resume TASK` or finish with `complete`. `complete` refuses to release an active recorded PID.

Send the controller the task ID, current state, first failing boundary, evidence path, and requested decision. If the controller cannot be reached, leave the task in `attention_required` or `blocked`; do not self-release it.

## Evidence and integration

Record the exact revision, worktree, command, target/fixture, first failure boundary, and artifact path. A build or test result is not a substitute for the product E2E layer required by Enchron's acceptance system. The controller decides integration and conflict resolution after validation.
