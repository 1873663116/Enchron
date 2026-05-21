# Exec Plan: HDR Full Frame Diagnostic Scan

## Goal

Add an explicit manual full-frame HDR diagnostic scan while keeping the default MPV drawable sample on the low-disturbance center ROI path.

## Scope

- Keep `MPV Drawable Sample` as the default center ROI sample.
- Add a separate `Full Frame Scan` action that is clearly manual and intrusive.
- Preserve delta safety: ROI and full-frame samples must not be mixed for ON/OFF comparison.
- Update diagnostics documentation and tests for region matching.

## Verification

- `swift test`
- `git diff --check`
- visionOS simulator app build when touched app-side Swift compiles cleanly.
