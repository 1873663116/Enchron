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

`Scripts/console/static_tier.py` wraps the existing checkers for the static tier.

`Scripts/console/report.py` renders human and JSON output and owns the exit codes.

Data lives in `Regression/units/` and `Regression/features/`.

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

Fifteen checks fail on a clean `main`. `product-source-comments`, `swiftlint` and `glass-usage` are among them, and all three are hard rules the repository sets for itself. Comment violations exist at `Modules/Playback/PlaybackRuntime.swift:1416`.

Runner channel latency, for the e2e tier. A command round trip is 0.65 s. A snapshot is 1.23 s, a tap 2.04 s, typing 2.55 s. Bringing a session up is 59 s at the median and 263 s at the worst.

A cold build for testing is about 13 minutes. Unit test execution is 7.4 s for 703 tests. The build dominates; the tests are a rounding error.

## Improving speed

Measure before changing. The tier reports its own duration in every run and writes `last-run.json`, so take the number from a run rather than from a wrapper that re-times it.

Attack in this order. First the largest single contributor. A check that takes 88 s while the median check takes 0.1 s is a defect in that check, not a cost of the tier.

Parallelism is available: the checks are independent processes. Any change here must keep one unit per call, so parallel fan-out belongs inside a tier, never across units.

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

## Traps

The gate scans `Scripts/console` now. Any module using `subprocess` or a timing primitive past `time.monotonic` must be in `Config/harness_primitives_allowlist.json`.

Adding a verb changes `vocab.py`, which is a rebuild. Adding a unit does not.

The channel has no cross-process lock. Two concurrent writers to `Documents/test-commands` corrupt each other. Serialization must come from the caller staying one-at-a-time.

`TidalEnvironmentTests.swift:10` raises `CancellationError` on a clean `main`. It is not caused by this infrastructure.
