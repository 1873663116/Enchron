---
name: doc-auditor
description: Use for Enchron documentation maintenance after code or docs diffs, named commits, stale-doc concerns, active documentation claim audits, document ownership checks, and human arbitration of documentation drift. Audits changed project facts against active docs, safely fixes mechanical drift, protects original requirements, historical decisions, contracts, product direction, architecture ownership, platform uncertainty, and release/legal/privacy/deployment boundaries, and prepares a three-part report before asking humans one decision at a time.
---

# Doc Auditor

This skill keeps Enchron's active documentation aligned with current project
truth. It is a boundary guide for documentation maintenance, not a
repository-wide checker, scorecard, or script.

## Scope Boundary

Audit the current diff, the user-named commits, or the documentation range the
user names. Expand to a broader repository audit only when the user explicitly
asks for that.

Treat a diff as a source of candidate fact changes. Confirm the current truth
from the strongest available source before editing documentation:

- Source code, Xcode project settings, build settings, target membership, and
  package manifests for repository facts.
- `ARCHITECTURE.md` and active contracts for architecture and module
  boundaries.
- `docs/product_philosophy.md` for product direction and strategic tradeoffs.
- `docs/ubiquitous_language.md` for shared terms.
- `.agents/skills/*` for agent routing and reference expectations.
- Apple documentation for platform behavior, API availability, privacy,
  App Store, media/HDR, ARKit, performance, and deployment facts.
- Explicit human decisions for product, architecture, release, legal, privacy,
  or historical interpretation.

When the repository or reading range is large, use subagents for focused
context gathering. Ask them for evidence and a short report, such as module
facts, active doc claims, inbound links, or whether a historical requirement is
still referenced. The main agent decides whether to read the source files more
deeply and whether any document should change.

## Document Identity

Classify each touched or conflicting document before changing it.

- `ARCHITECTURE.md` owns stable architecture boundaries, module
  responsibilities, dependency direction, invariants, and deliberate absences.
- `docs/product_philosophy.md` owns product principles, experience priorities,
  and strategic tradeoffs.
- `docs/ubiquitous_language.md` owns shared vocabulary.
- `docs/contracts/` owns active normative contracts.
- `docs/plans/active/` owns live execution plans with exits.
- `docs/reference/` owns durable investigations, diagnostics, and technical
  references; it becomes normative only when active architecture or contracts
  say so.
- `.agents/skills/` owns agent routing and task-specific operating guidance.
- `docs/archive/` owns historical material.
- Archived requirements and original requirements preserve the original
  historical request. Use them as evidence; keep their historical wording
  intact unless the user explicitly asks for archival editing.
- `docs/designs/` owns visual and design artifacts.
- `docs/solutions/` owns reusable troubleshooting or solution notes.

The goal is active documentation that matches the project. Historical material
may disagree with current project truth because it records an earlier state.

## Maintenance Boundaries

Make mechanical documentation maintenance directly when the current truth is
already established and the edit preserves meaning:

- Fix broken links, stale paths, and references to deleted files.
- Add or repair active-document purpose, status, owner/scope, or exclusion
  headers when the surrounding document already establishes them.
- Normalize terms to `docs/ubiquitous_language.md` when the semantic target is
  clear.
- Clean reference/archive status wording when a document's role is clear.
- Bring low-authority explanatory docs in line with clear high-authority facts.

Escalate semantic drift to humans after investigation:

- Architecture ownership changes.
- Product direction changes.
- Active contract conflicts.
- Original requirement or archived decision interpretation.
- Platform behavior uncertainty.
- Release, legal, privacy, signing, deployment, license, or compliance impact.
- Any change that would alter future agents' default understanding of the
  project.

Use `needs investigation` when the issue depends on evidence that has not yet
been checked, such as current build settings, target membership, package state,
uncommitted user edits, platform docs, or subagent reports.

## Human Arbitration

Before asking humans to decide semantic drift, produce a three-part report:

1. Summary: changed or exposed project facts and the affected documentation
   boundaries.
2. Self-decided maintenance: documentation edits already made, with the reason
   each was safe.
3. Pending arbitration: each unresolved issue, the conflicting facts or claims,
   the documents involved, and why the agent cannot decide automatically.

After the report, ask the human one arbitration question at a time. Each
question must require human judgment. Investigate discoverable facts before
asking.

## Output Shape

For automatic maintenance, report:

- Changed fact.
- Updated document.
- Why the edit was safe.
- Verification performed.

For pending arbitration, report:

- Changed fact.
- Owning boundary.
- Conflicting claim.
- Evidence checked.
- Why human decision is required.

For investigation-needed items, report:

- Missing evidence.
- Next evidence source: code, configuration, official docs, subagent report, or
  historical records.

Final handoff should separate automatic fixes, human arbitration, and remaining
investigation.
