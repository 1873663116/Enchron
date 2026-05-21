# Exec Plan: Nonblocking HDR Probe Readback

## Goal

Make HDR drawable probe safe enough for simulator/device smoke runs by preventing readback from blocking the main actor or the E2E harness indefinitely.

## Scope

- Keep GPU-first simulator behavior; do not restore the software fallback.
- Move MPV drawable readback behind an async timeout boundary so UI and smoke tests can continue when Metal readback stalls.
- Preserve center ROI default and explicit full-frame scan semantics.
- Keep probe conclusions conservative: timeout means readback unavailable, not HDR failure.

## Verification

- swift test
- git diff --check
- visionOS simulator build
- smoke HDR probe should write a timeout/no-drawable/result line instead of hanging.
