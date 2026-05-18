# ce-review: P1 Revalidation — Run 2026-04-05

## Scope

- **Mode**: headless (overnight)
- **Base**: a61c212 (full diff), focus on P1 fix commit f3aa757 (14 files, ~170 lines)
- **Intent**: Re-review to confirm 5 P1 fixes from R18 ce-review are resolved, no new P0/P1

## Review Team

- correctness-architecture (resident, combined)
- pattern-maintainability (resident, combined)
- adversarial-reviewer (conditional: 170 lines touching window lifecycle)
- testing-standards-agent (resident, combined)

## P1 Fix Verification

| P1 | Issue | Fix | Status |
|----|-------|-----|--------|
| #1 | Window lifecycle race (MainView) | 100ms debounce Task + cancellation | **RESOLVED** |
| #2 | Excessive env injection (XrPlayerApp→PlayerControls) | Centralized panoramaBridge to MainView onChange | **RESOLVED** |
| #3 | Binding setter async lag (FileBrowserSidebar) | @State + dual onChange bidirectional sync | **RESOLVED** |
| #4 | Width 680 duplication (PlayerControls/NLETimeline) | DesignTokens.Layout.playerControlsWidth | **RESOLVED** |
| #5 | cornerRadius hardcoding (10 files) | DesignTokens.Radius.card/.badge | **RESOLVED** |

## Findings

### New Findings (P2-P3)

| ID | Severity | File | Title | Reviewers | Confidence | Class |
|----|----------|------|-------|-----------|------------|-------|
| P2-1 | P2 | DesignTokenTests.swift | Missing test for Layout.playerControlsWidth | testing-standards | 0.85 | manual |
| P2-2 | P2 | DesignTokens.swift | Radius semantic loss: 6/8pt → badge(10pt) conflates distinct intent | adversarial, testing-standards | 0.78 | manual |
| P3-1 | P3 | MainView.swift:258 | 100ms debounce undocumented magic number | testing-standards | advisory | advisory |
| P3-2 | P3 | PlayerControlsView.swift | P1 #2 decoupling rationale not documented | testing-standards | advisory | advisory |

### Pre-existing Issues

| ID | Severity | File | Title | Reviewer | Confidence |
|----|----------|------|-------|----------|------------|
| PE-1 | P1 | MainView.swift | Detach-before-attach timing gap in immersive space transitions | adversarial | 0.72 |
| PE-2 | P2 | FileBrowserSidebar.swift | Sidebar connection failure not reflected in selection state | correctness | 0.88 |
| PE-3 | P2 | DesignTokens.swift | Badge namespace collision in Radius/Typography | pattern | 0.65 |

### Suppressed (< 0.60 confidence)

- Adversarial: "onChange bidirectional feedback loop" (0.55) — SwiftUI value identity prevents infinite loops
- Adversarial: "100ms debounce insufficient for animations" (0.45) — theoretical, no reproduction scenario

## Residual Risks

1. **Immersive space state machine race window** (pre-existing): panoramaBridge detach/attach not atomic with immersive space open/dismiss. Low probability in normal usage; rapid mode switching (<100ms) could expose gap.
2. **Radius consolidation visual delta**: 6→10pt (+67%) in ThumbStripView, 8→10pt (+25%) in DetailedTimelineView. Subtle but cumulative roundness increase. Requires human visual verification.

## Testing Gaps

1. No test for `DesignTokens.Layout.playerControlsWidth` (load-bearing constant)
2. No visual regression test for radius token consolidation
3. No integration test for debounce timing under rapid mode switching

## Verdict

**Ready to merge** — All 5 P1 fixes verified as RESOLVED. No new P0/P1. 2 P2 findings (missing test, semantic loss) are improvement suggestions, not blockers. Pre-existing issues documented for follow-up.
