# AgentOperability review protocol

Review exactly one `agent-operability` packet manifest. Do not review another packet in the same assessment. Do not run Simulator or device work, change product code, edit Catalog contracts, or issue a review receipt.

## Required inputs

Read the packet manifest and every file named by `units[].sourcePath`. Also read:

- `Regression/execution-protocol.md` for the Operation execution boundary;
- `Regression/oracle-protocol.md` for evidence adjudication;
- `.agents/skills/vp-e2e/SKILL.md` and the feature or reference files relevant to the packet;
- the current implementation and configuration files reached from those vp-e2e documents.

Catalog documents define the proposed regression contract. Code, configuration, and executable routes establish whether that contract is currently operable. A prose claim that names no real driver, state channel, fixture, or evidence route is not sufficient evidence of operability.

## Review each unit

For a Journey or Scenario, verify all of the following:

1. One Sidekick can finish the entire Scenario in one lease and one lane attempt.
2. Every Operation call has concrete arguments, a supported lane, a real current execution route, and sufficient outputs for later `result://` references.
3. Preparations can establish every prerequisite without a human runtime actor.
4. Every static case is represented by concrete ordered calls, and the archive contains the observations required to judge every obligation.
5. The Oracle and rubric can decide the SuccessExpression from obtainable evidence without inventing product semantics.
6. The cost is a plausible upper bound for the declared cases and bounded retries.
7. Journey ordering expresses only a real product or shared-state dependency. A MainGate dependency must remain lane-local and must not become a Journey join.

For a Preparation, verify idempotent setup, concrete fixture or account ownership, supported lane, executable calls, unique output key and schema, meaningful fingerprints, and complete dependency tag snapshots. Reject hidden human prompts or an output that cannot be reconstructed after retry.

For an Operation, verify that the versioned semantic action maps to a current vp-e2e controller, probe, or capture route. Its arguments must be sufficient to select that route; its declared result or evidence types must be obtainable; and its invalidation tags must describe the state the call can actually disturb. The action must not claim that a command return value alone proves product behavior.

For an Oracle or Rubric, verify that the declared evidence types are produced by current capture routes, every criterion is structurally decidable, negative controls distinguish invalid evidence from established failure, all static cases are conjunctive, and `Indeterminate` covers missing or mixed-provenance evidence. Reject subjective judgment, a human checkpoint, or an unnamed threshold that prevents autonomous adjudication.

## Decision boundary

Use `accepted` only when the unit is executable as written with the current repository and the reviewed external constraints recorded by the project. Use `rejected` when a missing driver, fixture, output, threshold, state binding, or evidence rule prevents autonomous execution or adjudication.

Do not resolve a HumanCoverage question. If an otherwise concrete unit depends on one, use `rejected` and name the exact `HC-nnn` question and the missing decision in the rationale. Continue reviewing every other unit in the packet so the assessment is complete. Do not reject merely because a decision is owned by HumanCoverage when that decision has already been represented as a concrete proposed contract and does not block execution.

Do not weaken a contract to make it pass. Do not treat a future implementation proposal as an existing execution route. Do not use majority voting or request a second reviewer.

## Assessment output

Write one canonical UTF-8 JSON object ending in one newline. The top-level keys and nested keys must use the lexicographic order shown below because `reviewctl` rejects non-canonical bytes:

```json
{"actor":{"actorId":"agent:operability:<packet-short-digest>","environmentDigest":"sha256:<digest>"},"issuedAt":"<RFC-3339 timestamp>","packetDigest":"sha256:<packet-digest>","reviewer":"agent-operability","schema":"enchron.regression.agent-operability-assessment","schemaVersion":1,"units":[{"contentDigest":"sha256:<unit-digest>","decision":"accepted-or-rejected","kind":"<unit-kind>","rationale":"<specific evidence and conclusion>","ref":"<unit-ref>"}],"usage":{"inputTokens":<approved inputTokens>,"reviewItems":<unit-count>}}
```

The `units` array must contain every manifest unit exactly once and in manifest order. Copy each `kind`, `ref`, and `contentDigest` exactly. Use the packet's approved `inputTokens` and the number of reviewed leaves as charged usage.

Compute `environmentDigest` as the canonical digest of this object:

```json
{"packetDigest":"sha256:<packet-digest>","protocolDigest":"sha256:<raw bytes digest of this file>","reviewRuntime":"codex-agent-operability-v1"}
```

Write the assessment under `.scratch/20260828-refactor-handoff/agent-operability-assessments/<packet-digest-without-prefix>.json`. Use `apply_patch` to create it. Run the owned JSON and packet validation locally, but do not call `reviewctl accept-agent`; the coordinator alone converts an all-accepted assessment into a report and receipt.

Report the assessment path, accepted and rejected unit counts, every rejected unit, and the evidence files inspected. A rejected assessment is a successful review result, not a worker failure.
