# Operation execution protocol

This file is the implementation locator for every Regression Catalog v1 Operation. The Operation contract supplies the action ID, version, arguments, supported lane, invalidation tags, and evidence types. This protocol supplies the execution boundary that turns that contract into one recorded call.

## Authorize each call

The capability gateway must authorize the exact `callId`, Operation ID, version, contract digest, canonical arguments, lane, attempt, and invocation limit before anything touches the target. `Scripts/regression/tools/op_tool.py` obtains that grant for the one call it runs; the authorization content is unchanged. The Agent executes calls in front-matter order. A `result://<call-id>/<field>` argument reads only the named field from an earlier successful call in the same lane and Scenario or Preparation attempt.

Reject a call before target access when its grant, version, digest, lane, argument set, or invocation count differs from the contract. Record the accepted invocation and every returned artifact with the same build identity, lane, Scenario attempt identity, `callId`, and capture time.

## Resolve the current driver

Read [the vp-e2e skill](../.agents/skills/vp-e2e/SKILL.md) before execution. Use its current controller command and evidence locations instead of copying a stale command from a Scenario. The following references define the executable paths:

- [Product driving and evidence](../.agents/skills/vp-e2e/references/product.md) defines session ownership, accessibility driving, state channels, and evidence provenance.
- [Simulator lane](../.agents/skills/vp-e2e/references/simulator.md) defines Simulator transport and Device Hub spatial input.
- [Device lane](../.agents/skills/vp-e2e/references/device.md) defines device transport, capture limits, and authorization failures.
- [Feature map](../.agents/skills/vp-e2e/features/README.md) routes product actions to the feature-specific drive and evidence sequence.
- `Scripts/verification/interactive_visionpro_ui.py` owns the shared session, accessibility actions, application commands, snapshots, and capture output.
- `Scripts/regression/tools/server.py` exposes the harness as MCP tools and runs one of them at a time under `--once`: `session` brings a device session up or takes it down, `op` runs one authorized Operation call, `bundle` assembles the anomaly bundle, `ledger` writes a verdict and reads the run, and `receipt` closes the run.
- `Scripts/verification/device_hub_canvas.py` owns Simulator gaze-and-pinch delivery.
- `Scripts/verification/journey_preflight.py` and the source-specific probes under `Scripts/verification/` own read-only fixture and remote-source checks.

## Name the lease holder, the session mode, and the known-defect ledger

`op` requires `--sidekick`, a `sidekick:<slug>` identifier naming who holds the lane lease. When the lane holds no active lease, `Scripts/regression/tools/op_tool.py` claims one for the node under that identity; when the lane already holds one, it refuses the call if the lease belongs to a different node or to a different sidekick. The identifier names the lease holder and nothing else. The Main-and-Sidekick scheduling layer retired on 2026-09-04, recorded in `Config/retired_documents.json`; `Scripts/regression/core/runtime.py`'s `MainRun`, driven one call at a time by these tools, replaced it, and no coordinator allocates leases or advances two lanes in parallel any more.

`session` takes `--mode`, either `agent` or `human`; the command line defaults it to `agent` and the MCP schema requires the field. Both modes bring the same controller session up on the `ensure` stage and take it down on the `halt` stage. `human` differs in one place: on `ensure`, and only when `--output-directory` is given, it opens `timeline.jsonl` under that directory, writes the first snapshot entry, and returns that path as `timeline` in the result. `Scripts/regression/tools/session_tool.py` keeps the file append-only and ordered by `recordedAt` -- an entry earlier than the last line already written is refused rather than filed, so a clock that stepped back cannot reorder the record -- and it supplies `mark` for one note and `poll_timeline` for repeated snapshots at 2.5-second intervals. The mode records a session; it adds no runtime decision point, and no Scenario waits on one.

`ledger write` consults the known-defect ledger at `Config/regression/known_defects.json` before it files a node as `failed`. Each record names one Scenario, a description, a `recorded` date, an `expiresWhen` condition, and exactly one `match`: either a registered `signature` or a `field`, `==`, `value` predicate read from the node's recorded fields. The first record whose Scenario and match both hit turns that node into `failed(known)`, which does not block a receipt, and the record itself is written into the verdict event beside the status so a replay reads which record spoke rather than inferring it. `failed(known)` cannot be requested; `Scripts/regression/tools/ledger_tool.py` derives it, and an empty `defects` array exempts nothing. `Scripts/regression/tools/known_defects.py` rejects a record that omits a field, leaves `expiresWhen` or `description` empty, names an unregistered signature, or compares with anything but `==`.

## Execute by Operation role

For `setup`, establish only the declared fixture or session state. Preserve the returned identity fields for later result references. Setup artifacts do not satisfy a coverage obligation.

For `product-behavior`, use the product's public interaction route described by the matching feature file. Record both the delivered interaction and the post-action application state. A command return value alone does not prove product behavior.

For `evidence`, read only the declared state channel or capture type. Store raw bytes before analysis. `evidence.archive` verifies provenance and writes one immutable bundle whose `observationRefs` name every source call included in the bundle.

For `diagnostic-bypass`, read or verify infrastructure state without assigning product coverage. A diagnostic result may explain an interruption, but it cannot satisfy a Promise.

## Map namespaces to drivers

`harness` and `app` calls use the shared controller lifecycle and application command channel. `navigation`, `accessibility`, `menu`, `media`, `playback`, `presentation`, `format`, `tracks`, `library`, `settings`, `cache`, and `issue` calls use the matching feature sequence and controller action. `input.device-hub-pinch` uses the Simulator Device Hub driver. `diagnostics` and `evidence` calls use the state and capture channels in the vp-e2e references. `host` calls use the named preflight or source probe and must return a receipt before any restore call. `source` calls combine the product browse route with the matching source preflight.

## Preserve the evidence boundary

An Operation proves only its declared semantic action and evidence outputs. It does not prove a Scenario's Promise, the correctness of another case, or readiness of another lane. Oracle evaluation remains separate and follows `Regression/oracle-protocol.md`.
