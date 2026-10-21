---
name: verify-console-session
description: Checks the console session machine against three promises with TLA+. Use before and after changing Scripts/console/daemon.py, Scripts/console/transport.py, or anything that launches, adopts, halts or records a runner.
---

# Verifying the console session machine

The console runs three processes: the operator, the resident daemon, and the
runner. The daemon and the runner outlive one command, so their interaction is
the only part of the console where events can interleave. This check models that
interaction and explores every reachable state.

## The promises

1. **One runner drives the device.** Two `xcodebuild` processes never talk to
   one device at the same time. Breaking this produces interleaved taps and
   corrupted evidence.
2. **One daemon owns the socket.** Two resident processes never both serve.
   Breaking this produces two sessions that halt each other, and every run pays
   the 23 s bring-up again.
3. **A held session is the live session.** When the daemon reports a session as
   already held, the runner behind it serves that session. Breaking this reports
   a healthy session, then fails the next command with "the session is gone".

## Run it

```bash
Scripts/console/formal/run.sh
```

Thirty seconds on a warm machine. It needs a Java runtime; `run.sh` fetches
`tla2tools.jar` into `Scripts/console/formal/` on first use and prints the
install line when no runtime answers.

Success prints `Model checking completed. No error has been found.` and exits 0.
A violation prints the invariant name and the step sequence that reaches it.

## Read a counterexample

TLC prints one state per step with variable assignments. The action names map to
code:

| Action | Code |
| --- | --- |
| `Ping`, `Spawn` | `ensure_running` in `daemon.py` |
| `EnsureReuse`, `EnsureAdopt`, `EnsureLaunch` | `Channel.ensure_session` |
| `Publish` | the runner writing `ready.json` |
| `RunnerDies` | `xcodebuild` exiting |
| `ForeignRunner` | a runner this daemon did not start |
| `DaemonCrash` | the daemon dying without halting |
| `IdleExit` | the idle window closing |
| `Invoke` | `Channel.invoke` |

A counterexample is steps in the code's own words. This one was real:

```
Ping, Spawn, EnsureLaunch, Publish, EnsureAdopt, RunnerDies, ForeignRunner
```

The daemon adopted a session, the runner died and left `ready.json` behind, an
unrelated runner appeared, and `alive()` still answered true because it compared
`held` with the stale file. The fix records the launched pid in
`.console/session.json` and requires that pid to be alive.

## Tell a real bug from a modeling error

A finding is a real bug when the action sequence maps to calls the code actually
makes, and the invariant is a promise the code means to keep. Before calling
something a bug:

- Confirm each action has a line in `daemon.py` or `transport.py`.
- Confirm the violated invariant is not simply too strong. An invariant that
  forbids a state the code is allowed to enter is a modeling error.
- Reproduce it with the real console when you can. Both findings above were
  reproduced by running the console, not only by the model.

A modeling error is fixed in `ConsoleSession.tla`. A real bug is reported with
the counterexample and fixed in the code, which then changes the model.

## Confirm the check still catches the break

A check never seen failing proves nothing. To confirm it, remove the ownership
guard from `EnsureAdopt` — drop the `/\ owned` line and add `/\ owned' = TRUE`,
with `owned` taken out of that action's `UNCHANGED` list — and rerun. It must
report `Invariant AliveImpliesLive is violated`. Undo the edit afterwards.

The same works for the second promise: in `Spawn`, replace the conditional with
`daemons' = daemons + 1`, and `AtMostOneDaemon` fails.

## What it does not cover

- The 22 controller verbs and the runner's own behaviour. The model treats a
  command as atomic.
- Timing. Liveness, timeouts and the 900 s idle window are constants here, not
  durations.
- Two devices, or one device driven from two worktrees. The model is one
  worktree, one device.
- The checker fan-out, the plan compiler, and evidence writing. Those are
  sequential or pure, and a model of them would restate the code.

## Keeping it in step

Covered files:

- `Scripts/console/daemon.py`: `ensure_running`, `Server.serve`, `Channel.alive`,
  `Channel.ensure_session`, `Channel.halt`, `Channel.invoke`
- `Scripts/console/transport.py`: `scoped_processes`, `send_command`
- `Scripts/console/channel` record file `.console/session.json`

Last confirmed to describe the code at commit `6dae9759`.

Move that commit forward only after checking that the model still names the same
actions and that `run.sh` passes. When the code gains a new way to reach a
session — a second daemon mode, a second runner launch path, a shared device —
add the action to `ConsoleSession.tla` first, then run it; a model without the new
path silently reports success.
