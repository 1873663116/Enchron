---
{"actor":{"actorId":"authority:approved-composite-design","environmentDigest":"sha256:bde0b0a17c23359f8ea6d8b37b2f31ece0dda6f367cee636b8afa1100cea725e"},"issuedAt":"2026-08-31T01:20:00Z","packetDigest":"sha256:be372679c71109ef70795ad670ebfd3e995d86cac3d9f48d2e2786749d8155e3","packetId":"review-packet:human-coverage-be372679c71109ef","reviewer":"human-coverage","schema":"enchron.regression.review-report","schemaVersion":1,"usage":{"inputTokens":5555,"reviewItems":4}}
---

# Derived HumanCoverage review

This report accepts `review-packet:human-coverage-be372679c71109ef` (`sha256:be372679c71109ef70795ad670ebfd3e995d86cac3d9f48d2e2786749d8155e3`).

The receipt is mechanically derived from the approved composite design. It records no new subjective judgment and introduces no runtime human step.

## Approved semantic authority

- Authority kind: `approved-composite-design-with-autonomous-evidence-resolution`
- Authority digest: `sha256:a25423e26d7c573d8ca49ef86c7854e9cb95d4dd245b3b4c3c3b8df70f666a28`
- Decision log: `Config/regression/semantic-authority-decisions.tsv` (`sha256:d5a08795fb2ed738806ef1ac44eb3a5811b0ef332d477b8f29411e7e833391a2`)
- Decisions: `HC-000, HC-001, HC-002, HC-003, HC-004, HC-005, HC-006, HC-007, HC-008, HC-009, HC-010, HC-011, HC-012, HC-013, HC-014, HC-015, HC-016, HC-017, HC-018, HC-019, HC-020, HC-021, HC-022, HC-023`
- Runtime human actor allowed: `false`
- Catalog digest: `sha256:480826f3b82c1246a5c3c67b251ef4d7fdbf627daf174b7738dc98625382a2fd`
- Review plan digest: `sha256:1a7d62e57b1ed7ef1a1f8e2498a50bbc3f4cc18eed6a166f0957ae33684f25e3`

## Packet units

- `journey:journey:webdav-source-lifecycle` `sha256:9e41c9677668f5315c2a0d4c2eebb4a8ca937b915eb3408646d11f67685975cc` from `Regression/journeys/webdav-source-lifecycle/journey.md`
- `scenario:scenario:webdav-source-lifecycle:certificate-trust-boundary` `sha256:8c0e8af2083e3a8fd7098ed2bdd1c78b6c133186266361c067047ff9202e4129` from `Regression/journeys/webdav-source-lifecycle/scenarios/certificate-trust-boundary.md`
- `scenario:scenario:webdav-source-lifecycle:webdav-add-source` `sha256:f33f1b1380b0bbd1916ce7d084b9b082bda381152cf1c38858a541590a999a3a` from `Regression/journeys/webdav-source-lifecycle/scenarios/webdav-add-source.md`
- `scenario:scenario:webdav-source-lifecycle:webdav-open-through-loopback` `sha256:c33b51036ec7d7415896af0d2584f047e51175ec5582c9851cdd7e3fa720cce1` from `Regression/journeys/webdav-source-lifecycle/scenarios/webdav-open-through-loopback.md`
