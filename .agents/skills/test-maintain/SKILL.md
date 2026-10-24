---
name: test-maintain
description: Use when changing the console test infrastructure itself, proving it stays correct, or improving how fast a tier runs. Covers the module layout, the correctness argument, the measured baselines, and the acceptance checklist.
---

# Maintaining the test infrastructure

The console is the only test entry in this repository. This skill covers changing it and proving the change is sound.

## Layout

`Scripts/console/cli.py` parses arguments and dispatches. It holds no verification logic.

`Scripts/console/model.py` holds the frozen value types. No disk access.

`Scripts/console/vocab.py` is the verb closed set. A verb carries its tier, the capabilities it needs, whether it occupies a lane, its parameters, the evidence it produces and its budget. Editing this file is the only change that needs a rebuild.

`Scripts/console/loader.py` reads unit and feature files, and refuses a unit without a terminal.

`Scripts/console/compile.py` turns a unit into a frozen plan. It is a pure function of values. Every definition error is decided here.

`Scripts/console/machine.py` probes capabilities, or builds a synthetic profile so CI can compile Mac-only units on a Linux machine.

`Scripts/console/engine.py` executes a plan, writes evidence and produces a report.

`Scripts/console/guard.py` holds the single guardrail mechanism. The three guardrail kinds are data, not code paths.

`Scripts/console/static_tier.py` wraps the existing checkers. The full text set and the eight-checker code-only lane both live here.

`Scripts/console/merge_gate.py` runs the merge gate: CI, build and unit, classified against the declarations and override records main carries.

`Scripts/console/ops.py` runs a single operation for debugging, records and replays debug sessions, and scaffolds a unit draft. It writes under `.scratch/console/debug/` and never under `TestEvidence`.

`Scripts/console/build_tier.py` runs the build and unit tiers.

`Scripts/console/daemon.py` holds the session, speaks the socket protocol, launches the runner, and recovers a dead runner.

`Scripts/console/transport.py` speaks the runner protocol: command file, Darwin notification, response file. It also scopes runner processes to this worktree, so a run in another worktree is never touched. It stages host media into the app's `Documents/TestMediaInbox` for the import command.

`Scripts/console/report.py` renders human and JSON output and owns the exit codes.

Data lives in `Config/console/units/` and `Config/console/features/`.

## References

- Generated catalog units, translator ownership and cold-start cases: [references/translation.md](references/translation.md).
- Unit action options and field semantics: [../test/references/unit-actions.md](../test/references/unit-actions.md).
- CI machine preparation, check tags and identity registry: [references/ci.md](references/ci.md).

## The state machine

Three machines run at once: the operator's process, the resident daemon, and the
runner. Only the daemon outlives one command. Read this before debugging anything
that behaves differently on the second run.

### One `console run`

```
  argv
   │
   ├─ LoadRefusal (C001–C015) ──> exit 3 or 4, nothing started
   ▼
  compiled plan ────────────────> plan.json written
   │
   ▼
  step loop, one step at a time, never in parallel
   │        │
   │        ├─ static.check ──> checker subprocess ──> exit code
   │        └─ device.*     ──> daemon ──> transport ──> runner
   │
   ├─ guardrail trips ──> verdict blocked, remaining steps skipped
   ▼
  terminal check, evaluated even when a step failed
   │
   ▼
  verdict passed | failed | blocked ──> report.json, index.jsonl, exit code
```

The terminal check decides the verdict on its own. A failed step does not skip
it, and a written artifact does not rescue a failed step. Both are recorded.

### The daemon

```
  absent ──ensure_running──> starting ──ping answers──> listening
     ▲                          │                          │
     │                          └── no ping in 15 s ──────┘
     │                                                     │
     └──── no request for 900 s, halts the session ────────┘
                                                           │
     ┌─────────────────────────────────────────────────────┘
     ▼
  listening ──op=ensure──> holds a session ──op=invoke──> command in flight
```

The exit is measured from the last request, not from startup. A daemon in use
does not exit.

### The session

```
  none ──ensure──> launching ──ready.json published──> ready
    ▲                  │                                  │
    │                  └── 300 s without ready ───────────┤
    │                                                     │
    └────────── runner exited, or halt ───────────────────┘
```

`halt` kills every runner this worktree started before it launches another, so
two runners never drive one device. The cost is that a second daemon claiming
the same worktree kills the first one's session.

A lane is one target device. Each target gets its own socket at
`$TMPDIR/enchron-console-<digest>.sock`, derived from the worktree and the
target, and its own `.console/session-<target>.json`. Two targets therefore run
side by side from one worktree without touching each other. The socket lives
outside the worktree because a Unix socket path stops working at about 100
characters, and this repository's worktree paths are already long.

Ownership lives in `.console/session-<target>.json`: the daemon records the pid it
launched and the sessionID that runner published. A session counts as held only
while that pid is alive, `ready.json` still names that session, and the two
agree. Without the record, a stale `ready.json` plus any live runner reads as a
held session and the next command fails.

### What the states tell you

| Symptom | State | Move |
| --- | --- | --- |
| `no daemon socket` | absent | `console daemon start` |
| `the session is gone; ensure it again` | runner died while held | rerun; the next ensure relaunches |
| Runs take 24 s every time | launching, never ready | check `.console/runner.log` |
| Runs take 24 s after a good one | second daemon halted the first | run one daemon per worktree |
| `blocked` with a guardrail name | guardrail tripped | raise the budget in the unit |
| Passing step, failed terminal | artifact missing or empty | read the evidence directory |

`python3 Scripts/console/cli.py daemon status` answers the daemon state and
`daemon stop` halts it. The session machine's three promises, the TLA+ check and
the counterexample reading are in verify-console-session.

Installing a new app build retires the runner session: stop the daemon, delete
`.console/session-*.json`, start it again, and run one unit before trusting any
other. A session that dies mid run is re-ensured and the command retried once,
and a daemon socket that is gone is rebuilt before the next request. The daemon
keeps the code it started with, so stop and start it after editing anything it
runs.

## Running lanes in parallel

Three things are serial and stay serial: the steps inside one unit, the units
inside one run, and the commands inside one daemon. Everything else can overlap.

| Axis | State | Limit |
| --- | --- | --- |
| Checkers inside the static tier | serial, measurably 4x available | the longest single check sets the floor |
| Device lane beside simulator lane | works now, one daemon per target | none observed |
| Several simulators on one Mac | works now | needs an M-series Mac with 32 GB or more; this machine has 16 GB and must not |
| Several Macs | works, each Mac is its own worktree and lane | none |
| Several physical devices on one Mac | unverified | each needs its own daemon and its own provisioning |

Take the static tier first: read its current check count, duration and slowest
check from `last-run.json`. A fan-out needs to know which checks may sit beside
another, because a check that boots a simulator or binds a port serialises with
its peers.

## Reading a failure

Every check carries three tags: the environment it needs, what its failure
means, and who has to act. A failure line prints the last two, so the first
token of a failure names the owner.

| Axis | Values |
| --- | --- |
| environment | text, toolchain, simulator, services |
| authority | blocking, reporting, precondition |
| attribution | product, infrastructure, release |

Registered checks take their tags from `CHECK_TAGS` in
`Scripts/rules/run_verification.py`. A registered check without an entry is
reported by `untagged` and fails its self-test. Discovered test checks inherit
`DISCOVERED_TAGS`, and the few that need a live service override the environment
through `DISCOVERED_TAGS_OVERRIDES`.

Checks a quick run does not reach are listed under `unevaluated` rather than
counted as passing.

## The correctness argument

Three properties carry the design.

**Definition errors are decided before any device, build or network touch.** `compile.py` takes only values. `plan check --all` therefore runs on any machine and reports every refusal without a Mac.

**One unit per call is structural.** `run` and `plan compile` take a single positional unit. There is no `--all` on either. A batch can only exist where nothing executes.

**The terminal is required.** A unit without one is refused at load with `C001`, not degraded at run time. Without it the guardrails cannot separate an expected confirmation from an unexpected one.

To prove a change preserves these, run `python3 -m unittest discover -s Scripts/console/tests`. The suite asserts each refusal code, the single-unit rule and a clean compile.

## Measurement and speed

Measure before changing. Every tier writes its duration and per-check breakdown
to `last-run.json`, and the merge gate keeps its runs under
`TestEvidence/console/merges/`; the current tier durations and the end-to-end
unit distribution are in docs/UI_TEST_HARNESS_CONSTRAINTS.md 的实测章节.

Cold session bring-up measured 23 s on this machine; the docs record the same
command at about 24 s on the simulator lane and 115–286 s on the device lane.
The split, from the runner log:

| Phase | Cost |
| --- | --- |
| `halt` with nothing running | 0.2 s |
| `xcodebuild` start to the runner process | 3.5 s |
| XCUITest setting up the automation session | 4.0 s |
| waiting for the app to go idle | 4.8 s |
| finding the target application | 5.6 s |
| first accessibility snapshot | 1.7 s |

Everything after the runner process starts is XCUITest attaching to a large
visionOS app, so no change to this repository makes that cheaper. The cost is
paid once per session and then sits at 0.16 s per reuse, which is why the
resident daemon exists.

`console` process startup is about 40 ms and a unit compile about 2–3 ms, so
`plan check --all` stays cheap. The console self-test suite runs in 0.43 s. A
command round trip is 0.65 s, a snapshot 1.23 s, a tap 2.04 s and typing 2.55 s.
A cold build for testing is about 103 s and the 686 unit tests run in about 7 s;
the build dominates.

Attack in this order: the longest self-test that sets the slow-path floor, then
the slowest scanner on the fast path, then the fan-out. A scanner that costs
several seconds on a one-line change is a defect in that scanner. Parallelism
stays inside a tier (see Running lanes in parallel); one unit per call stays
structural.

A slow e2e loop is usually a cold session: a warm daemon is the fix, not a
faster bring-up.

Keep coverage honest: a slower tier that runs every check beats a tier that
skips checks to hit a number.

`Config/swiftlint_baseline.json` holds a baseline so a build can pass on a tree
that already broke a rule; a new finding fails, and one that disappears also
fails until the baseline shrinks.

The prose comment rule holds no baseline. Every first-party text file is
scanned: Swift, C, Python, shell, YAML, plist and JSON. Exemptions come only
from `Config/third_party_sources.json`, which lists the vendored paths and the
provenance of adapted files; a license header outside that registry fails.

Neither baseline hides debt. Widening one is refused, so the only way to clear
an entry is to fix the code.

## Acceptance checklist

The change is done when every line holds.

- `console doctor` reports the tiers this machine can run, and names what is missing on one that cannot run them.
- `console --machine linux tier build` exits 4 and names the missing capabilities.
- `console plan check --tier static` runs with no Mac, no device and no build.
- A unit with no terminal is refused with `C001`, at load, with no flag to override.
- `console run UNIT UNIT` is a usage error.
- Adding, editing and removing a unit each end with a clean compile and one passing run.
- Removing a unit a feature still names reports `C012`; a unit no feature names reports `C013`; an unknown verb reports `C003`.
- A run writes `plan.json`, `report.json` and `steps/` under `TestEvidence/console/<unit>/<stamp>/`, and `index.jsonl` gains one line.
- `python3 -m unittest discover -s Scripts/console/tests` and `python3 Scripts/rules/harness_primitives_gate.py` pass.
- The static tier's duration and per-check breakdown come from a real run.
- A build runs `console tier static --code-only` before Sources; a commit and a push run `console plan check` plus the changed-scope static tier.
- A merge into main runs `console merge check` and records its status in the commit message.
- A failed `run` prints the failing step, the expected and actual detail, the evidence directory and a rerun command.
- `console op`, `console replay` and `console unit scaffold` stay under `.scratch/console/debug/`; the scaffold still needs an assertion and a feature reference.
- Green and yellow allow the merge, a valid override allows it and records itself, red aborts it; declarations and overrides count only from main.
- `console tier build` and `console tier unit` name the missing capability on a machine that cannot run them.
- `console daemon start`, `status` and `stop` answer, and a run adopts an already-live session in about 100 ms.

## Traps

The gate scans `Scripts/console`. Any module using `subprocess` or a timing primitive past `time.monotonic` must be in `Config/harness_primitives_allowlist.json`.

