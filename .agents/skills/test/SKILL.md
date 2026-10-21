---
name: test
description: Use when verifying a change end to end, reviewing a unit or feature map, or adding, editing and removing test units. Covers the console CLI, its four tiers, and how to read a refusal.
---

# Test infrastructure

`Scripts/console/cli.py` is the single entry for verification. It replaces `runctl`, `tools/server.py` and `interactive_visionpro_ui.py`.

## Four tiers

`static` reads source text. Any machine. Seconds. This is the whole of CI.

`build` compiles the app. Mac with Xcode. Minutes.

`unit` runs the unit tests. Mac with Xcode. The build must already exist.

`e2e` drives the interface. Mac with a simulator or a device.

`console tier static` runs the existing checkers. `console tier build --machine mac` reports the missing capability instead of pretending to work.

## Three concepts

A **feature map** is one complete verification, made of units in order. It lives in `Regression/features/`.

A **unit** is an ordered group of actions and the smallest thing you run. It lives in `Regression/units/`.

An **operation** is one interface interaction. Atomic actions only.

A promise is an acceptance statement on a feature map. A precondition is a field on a unit. A judgement is a layer 3 operation.

## Unit fields

Six fields, `terminal` required.

`id`, `layer` (2 or 3), `actions`, `terminal`, `requires`, `role`.

A unit without `terminal` is refused at load. The guardrails cannot tell an expected confirmation from an unexpected one without it.

`requires` names the capabilities the unit needs. Missing it means no special requirement. `role` defaults to `unstated`.

## Commands

`console doctor` prints the capabilities of this machine and the tiers it can run.

`console list` lists units with their layer and requirements.

`console plan check --tier static` compiles every unit without touching a device or a build. This is the whole offline gate.

`console plan show UNIT --tier e2e` prints one compiled plan with its digest.

`console run UNIT --tier e2e` runs one unit and writes evidence.

`console tier static --quick` runs the checkers.

## One unit per call

`run` accepts exactly one unit. A second unit is a usage error. There is no `--all` on `run`. Batches exist only in `plan check --all`, which compiles and reports without executing.

Do not write a script that loops `console run` over many units to get one long pass. Each call is a step you read before the next, and a failure inside a unit is a bug to fix, not something to retry past.

## Refusals

Codes name the rule. The message names the fix.

`C001` no terminal. `C002` bad layer or duplicate id. `C003` verb outside the vocabulary, which needs a recompile. `C004` the machine lacks a capability the unit requires. `C005` malformed action. `C006` layer and tier disagree. `C007` a verb needs a capability the unit does not declare. `C008` the terminal path is produced by no verb. `C009` a layer 3 unit cannot terminate on exit. `C012` a feature map names a unit that does not exist. `C013` no feature map reaches this unit. `C015` daemon transport without that capability.

Exit codes. 0 passed. 1 terminal not met. 2 usage. 3 refused. 4 missing capability. 5 guardrail stopped the run. 6 engine fault.

## Evidence

Every run gets a directory under `TestEvidence/console/<unit>/<stamp>/`. It holds `plan.json`, `report.json` and `steps/`. `index.jsonl` appends one line per run.

Nothing is deleted. A passing run can still be wrong, so its evidence stays.

## Changing units

Adding, editing and removing are data changes. They take effect on the next call, with no rebuild.

After any of the three, run `console plan check --tier static` and then run the unit once. A reload message alone proves nothing.

Removing a unit still named by a feature map fails with `C012`. Removing the feature reference first makes the unit an orphan, which fails with `C013`. Both paths are the intended way to delete.

Editing an action to use a verb outside `vocab.py` fails with `C003`. Adding that verb is a runtime change and needs a rebuild of the console.

## Guardrails

Three, sharing one mechanism, evaluated around every step: an unexpected dialog, a step over its budget, a context that drifted. All three abort the unit and report.

A product failure stops the unit and is yours to investigate. A tool failure, such as a dead session or a dropped runner, is recovered by the executor.

## Builds

Simulator builds must name the concrete simulator. `-destination 'platform=visionOS Simulator,id=<UDID>'`. `generic/platform=visionOS Simulator` builds arm64 and x86_64, and `RealityKitScripting.xcframework` has no x86_64 simulator slice, so that pass cannot link.
