# Operation execution protocol

This file is the implementation locator for every Regression Catalog v1 Operation. The Operation contract supplies the action ID, version, arguments, supported lane, invalidation tags, and evidence types. This protocol supplies the execution boundary that turns that contract into one recorded call.

## Authorize each call

Main must authorize the exact `callId`, Operation ID, version, contract digest, canonical arguments, lane, attempt, and invocation limit before an Agent touches the target. The Agent executes calls in front-matter order. A `result://<call-id>/<field>` argument reads only the named field from an earlier successful call in the same lane and Scenario or Preparation attempt.

Reject a call before target access when its grant, version, digest, lane, argument set, or invocation count differs from the contract. Record the accepted invocation and every returned artifact with the same build identity, lane, Scenario attempt identity, `callId`, and capture time.

## Resolve the current driver

Read [the vp-e2e skill](../.agents/skills/vp-e2e/SKILL.md) before execution. Use its current controller command and evidence locations instead of copying a stale command from a Scenario. The following references define the executable paths:

- [Product driving and evidence](../.agents/skills/vp-e2e/references/product.md) defines session ownership, accessibility driving, state channels, and evidence provenance.
- [Simulator lane](../.agents/skills/vp-e2e/references/simulator.md) defines Simulator transport and Device Hub spatial input.
- [Device lane](../.agents/skills/vp-e2e/references/device.md) defines device transport, capture limits, and authorization failures.
- [Feature map](../.agents/skills/vp-e2e/features/README.md) routes product actions to the feature-specific drive and evidence sequence.
- `Scripts/verification/interactive_visionpro_ui.py` owns the shared session, accessibility actions, application commands, snapshots, and capture output.
- `Scripts/verification/device_hub_canvas.py` owns Simulator gaze-and-pinch delivery.
- `Scripts/verification/journey_preflight.py` and the source-specific probes under `Scripts/verification/` own read-only fixture and remote-source checks.

## Execute by Operation role

For `setup`, establish only the declared fixture or session state. Preserve the returned identity fields for later result references. Setup artifacts do not satisfy a coverage obligation.

For `product-behavior`, use the product's public interaction route described by the matching feature file. Record both the delivered interaction and the post-action application state. A command return value alone does not prove product behavior.

For `evidence`, read only the declared state channel or capture type. Store raw bytes before analysis. `evidence.archive` verifies provenance and writes one immutable bundle whose `observationRefs` name every source call included in the bundle.

For `diagnostic-bypass`, read or verify infrastructure state without assigning product coverage. A diagnostic result may explain an interruption, but it cannot satisfy a Promise.

## Map namespaces to drivers

`harness` and `app` calls use the shared controller lifecycle and application command channel. `navigation`, `accessibility`, `menu`, `media`, `playback`, `presentation`, `format`, `tracks`, `library`, `settings`, `cache`, and `issue` calls use the matching feature sequence and controller action. `input.device-hub-pinch` uses the Simulator Device Hub driver. `diagnostics` and `evidence` calls use the state and capture channels in the vp-e2e references. `host` calls use the named preflight or source probe and must return a receipt before any restore call. `source` calls combine the product browse route with the matching source preflight.

## Preserve the evidence boundary

An Operation proves only its declared semantic action and evidence outputs. It does not prove a Scenario's Promise, the correctness of another case, or readiness of another lane. Oracle evaluation remains separate and follows `Regression/oracle-protocol.md`.
