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

`Scripts/console/static_tier.py` wraps the existing checkers. The full quick set and the eight-checker code-only lane both live here.

`Scripts/console/build_tier.py` runs the build and unit tiers.

`Scripts/console/daemon.py` holds the session, speaks the socket protocol, launches the runner, and recovers a dead runner.

`Scripts/console/transport.py` speaks the runner protocol: command file, Darwin notification, response file. It also scopes runner processes to this worktree, so a run in another worktree is never touched.

`Scripts/console/report.py` renders human and JSON output and owns the exit codes.

Data lives in `Config/console/units/` and `Config/console/features/`.

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

```bash
python3 Scripts/console/cli.py daemon status
python3 Scripts/console/cli.py daemon stop
python3 Scripts/console/formal/run.sh
```

The last command checks the session machine against three promises. It needs a
Java runtime, and it fetches `tla2tools.jar` on first use.

## Where the seconds go

Cold session bring-up measured 23 s. The split, from the runner log:

| Phase | Cost |
| --- | --- |
| `halt` with nothing running | 0.2 s |
| `xcodebuild` start to the runner process | 3.5 s |
| XCUITest setting up the automation session | 4.0 s |
| waiting for the app to go idle | 4.8 s |
| finding the target application | 5.6 s |
| first accessibility snapshot | 1.7 s |

The app itself launches from `simctl` in 0.4 to 1.0 s. Everything after the
runner process starts is XCUITest attaching to a large visionOS app, so no
change to this repository makes that cheaper. The cost is paid once per session
and then sits at 0.16 s per reuse, which is why the resident daemon exists.

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

The tier is the axis worth taking next: 193 checks run one after another for
364 s while the longest single check is 82 s. A fan-out needs to know which
checks may sit beside another, because a check that boots a simulator or binds a
port serialises with its peers.

## Identity and credentials

`Config/test_service_identities.json` names every variable that carries an
identity and the service it belongs to. The registry holds names, never values.
Values live in the environment or in `.env`, which is ignored.

`Scripts/rules/verify_test_service_identities.py` reads the registry and reports
three things: a variable that appears in the tree but not in the registry, a
value from the environment found anywhere in the tree, and four credential
shapes that need no registry at all — a private key block, a credential inside a
URL, a literal authorization header, a certificate fingerprint.

A new supplier is one registry entry. A supplier that is never registered fails
on its first commit, which is the point: forgetting to maintain the registry is
an error, not a silent gap.

The identity classes in `check_no_literal_rfc1918.py` read the account name from
`EMBY_USER`, `SMB_USER` and `WEBDAV_USER` instead of carrying the literal. When
none is set, that scan reports nothing and the shape rules still run.

## The correctness argument

Three properties carry the design.

**Definition errors are decided before any device, build or network touch.** `compile.py` takes only values. `plan check --all` therefore runs on any machine and reports every refusal without a Mac.

**One unit per call is structural.** `run` and `plan compile` take a single positional unit. There is no `--all` on either. A batch can only exist where nothing executes.

**The terminal is required.** A unit without one is refused at load with `C001`, not degraded at run time. Without it the guardrails cannot separate an expected confirmation from an unexpected one.

To prove a change preserves these, run `python3 -m unittest discover -s Scripts/console/tests`. The suite asserts each refusal code, the single-unit rule and a clean compile.

## Baselines

Measured on this repository, 2026-10-21.

`console` process startup, including stdlib imports, is about 40 ms.

A unit compile is about 2 to 3 ms. `plan check --all` over the whole repository is single digit milliseconds per unit.

The self-test suite runs in 0.43 s.

`static` tier with `--quick` took 371 870 ms. The checkers themselves account for roughly 318 s: 194 checks, of which the six slowest take 63 percent. `test-generate-reachability-inventory` alone is 88 s.

The branch carries the console plus every `main` commit it was built against, and it merges into `main` with no conflicts. Re-check after a merge that both baselines still pass, because code arriving from `main` can bring findings the console has never seen.

`Config/swiftlint_baseline.json` holds a baseline so a build can pass on a tree that already broke a rule; a new finding fails, and one that disappears also fails until the baseline shrinks.

The prose comment rule holds no baseline. Every first-party text file is scanned: Swift, C, Python, shell, YAML, plist and JSON. Exemptions come only from `Config/third_party_sources.json`, which lists the vendored paths and the provenance of adapted files; a license header outside that registry fails.

Neither baseline hides debt. Widening one is refused, so the only way to clear an entry is to fix the code.

Runner channel latency, for the e2e tier. A command round trip is 0.65 s. A snapshot is 1.23 s, a tap 2.04 s, typing 2.55 s. Bringing a session up is 59 s at the median and 263 s at the worst.

A cold build for testing is about 13 minutes. Unit test execution is 7.4 s for 703 tests. The build dominates; the tests are a rounding error.

## Improving speed

Measure before changing. The tier reports its own duration in every run and writes `last-run.json`, so take the number from a run rather than from a wrapper that re-times it.

The measured shape of the static tier: 193 checks, 364 s wall, run one after another. The longest single check is 82 s (`test-generate-reachability-inventory`), the next is 59 s (`playback-core-tests`), and the median is well under a second. Running the independent ones concurrently bounds the tier at the longest single check, so the ceiling is roughly four times faster. Anything beyond that needs the two slow checks to be split or cached.

Attack in this order. First the two checks that set the floor. A check that takes 82 s while the median check takes 0.1 s is a defect in that check, not a cost of the tier. Then the fan-out, which is the second fourfold.

Parallelism is available: the checks are independent processes. Any change here must keep one unit per call, so parallel fan-out belongs inside a tier, never across units. Not every check is safe to run beside another: one that boots a simulator or binds a port serialises with its peers, and the fan-out has to know which is which.

The session is not the bottleneck it looks like. Bring-up costs 23 s cold and 0.16 s when the daemon already holds a session, so the fix for a slow e2e loop is a warm daemon, not a faster bring-up.

Do not trade coverage for a headline number. The tier may be slower than its target and still be honest; a tier that skips checks to hit a number is worse than no tier.

## Acceptance checklist

The refactor is done when every line holds.

- `console doctor` reports the tiers this machine can run, and names what is missing on one that cannot run them.
- `console --machine linux tier build` exits 4 and names the missing capabilities.
- `console plan check --tier static` runs with no Mac, no device and no build.
- A unit with no terminal is refused with `C001`, at load, with no flag to override.
- `console run UNIT UNIT` is a usage error.
- Adding a unit, editing one, and removing one each have a path: a clean compile after the change, then one `run` that passes.
- Removing a unit a feature still names reports `C012`. A unit no feature names reports `C013`.
- Using a verb outside the vocabulary reports `C003` and says a recompile is needed.
- A run writes evidence under `TestEvidence/console/<unit>/<stamp>/` with `plan.json`, `report.json` and `steps/`.
- `index.jsonl` gains exactly one line per run.
- `python3 -m unittest discover -s Scripts/console/tests` passes.
- `python3 Scripts/rules/harness_primitives_gate.py` passes, with `Scripts/console` inside its scan roots.
- `static` tier duration and its per-check breakdown are available from a real run.
- A build runs `console tier static --code-only` before Sources, and a forbidden comment fails that build.
- A push runs `console plan check` and `console tier static --quick`, and skips both when the diff touches no code.
- `console tier build` and `console tier unit` name the missing capability on a machine that cannot run them.
- `console daemon start`, `status` and `stop` all answer, and a run adopts an already-live session in about 100 ms.

## Traps

The gate scans `Scripts/console` now. Any module using `subprocess` or a timing primitive past `time.monotonic` must be in `Config/harness_primitives_allowlist.json`.

Adding a verb changes `vocab.py`, which is a rebuild. Adding a unit does not.

The channel has no cross-process lock. Two concurrent writers to `Documents/test-commands` corrupt each other. Serialization must come from the caller staying one-at-a-time.

`TidalEnvironmentTests.swift:10` raises `CancellationError` on a clean `main`. It is not caused by this infrastructure.
