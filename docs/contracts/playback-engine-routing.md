# Playback Engine Routing Contract

Status: Active normative contract.
Scope: Playback launch, production playback core ownership, session ownership, and UI-facing playback semantics.
This file is not product rationale, vocabulary, a reference investigation, or an Apple media capability study.

## Summary

Enchron uses one production playback core per playback session.

The current production route is **mpv-first**. Playback implementation should
converge around mpv for playback, compatibility, open formats, complex
subtitles/tracks, remote I/O, HDR experiments, and future immersive rendering
exploration.

Apple AV / AVFoundation / AVKit are reference, diagnostics, subjective visual
comparison, HDR/EDR observation, and future platform investigation surfaces.
They are not the current production playback engine, default fallback, second
production core, or target branch of current engine routing.

Product rationale belongs in `docs/product_philosophy.md`. Vocabulary belongs
in `docs/ubiquitous_language.md`. High-level module ownership belongs in
`ARCHITECTURE.md`.

## Production Engine

Current production engine:

- `mpv`

Reserved or diagnostic labels may appear in plans, debug UI, probes, or future
research, but they do not become `PlaybackEngineRoute.selectedEngine` values
for current production playback.

## Router Inputs

The current route may use:

- source URL
- source type: local file, SMB, WebDAV, HTTP(S), Photos asset, app-provided
  asset, and future source types
- extension and detected container
- available metadata
- metadata evidence quality: runtime-detected, prefetched, persisted, inferred,
  placeholder, or unknown
- remote/local source classification
- detected or inferred `MediaProfile` hints
- required session capabilities

Required session capabilities may include:

- needs frame output
- needs custom texture surface
- needs panorama projection
- needs stereoscopic projection
- needs reliable audio track selection
- needs reliable subtitle selection
- needs external subtitle support
- needs frame stepping
- needs HDR metadata evidence
- needs remote seek reliability

These are domain capability requirements. They are not UI-level engine
branches.

AVFoundation or AVKit metadata may be used as supporting evidence for
diagnostics or media-profile research. It does not imply an Apple AV production
route.

## Router Output

The router returns a `PlaybackEngineRoute`.

A route contains:

- `selectedEngine`: `mpv` or `none`
- `reasonCode`: stable machine-testable reason
- `decisionBasis`: evidence used by the route
- `requiredCapabilities`: capabilities this route is expected to satisfy
- `fallbackPolicy`: `none` or same-engine retry policy
- `unsupportedReason`: present when `selectedEngine` is `none`

`reasonCode` should be stable enough for tests. Example reason codes:

- `mpvProductionCore`
- `openFormatContainer`
- `complexSubtitleModel`
- `complexAudioTrackModel`
- `remoteIORequiresMPV`
- `customTextureSurfaceRequired`
- `panoramaProjectionRequired`
- `hdrMpvExperiment`
- `placeholderMetadataInsufficient`
- `requiredCapabilityUnavailable`
- `unsupportedSource`
- `futureAppleNativeProfileUnsupported`

## Hard Session Contract

One playback session owns exactly one production playback core.

The production playback core is decided before user-visible playback starts.

No parallel production playback cores are allowed for one session.

No dual product state machine is allowed.

No session-time switching between mpv and Apple AV is allowed.

`PlayerUI` must not branch on concrete adapter type or diagnostic renderer.

`PlaybackEngineRoute` is not `PlaybackMode`.

`PlaybackMode` remains a presentation decision: window, immersive scene, or
panorama.

## Launch Flow

Both direct playback and prepare/confirm playback must pass through the same
launch contract.

`PlaybackLaunchCoordinator.preparePlayback` may collect metadata and create a
route candidate, but must not start multiple playback cores.

A route candidate is valid only for the matching launch generation and source
fingerprint.

`confirmPlayback` must receive or recompute a valid route before actual
playback starts.

Placeholder metadata is not authoritative route evidence.

Persisted metadata, inferred metadata, prefetched metadata, and
runtime-detected metadata are not equivalent. The route must preserve evidence
quality.

## Fallback

Same-engine retry is not cross-engine fallback.

Same-engine retry may occur inside the selected mpv route when the session
remains owned by mpv.

Apple reference playback is not a production fallback.

After the first visible frame, audible playback, or user-visible playing state
is published, the session must not switch playback cores.

A later fatal engine failure ends the session. Retrying starts a new playback
session.

## UI Boundary

`PlayerUI` speaks only:

- `PlaybackControlling`
- `MediaProfile`
- `ProjectionType`
- `HDRType`
- `HDROutputMode`
- `AudioTrack`
- `SubtitleTrack`
- `PlaybackState`
- `PlaybackPosition`
- shared domain capability states

The UI may react to capability availability, unsupported states, and media
facts.

The UI must not branch on `MPVPlayerAdapter`, Apple reference playback,
diagnostic renderer identity, `mpv`, or `appleAV`.

## Frame Output

Frame output is a shared domain capability.

An adapter may report frame output available, unavailable because the current
surface owns rendering, or unsupported for the requested presentation path.

`PlayerUI` and `SpatialScene` must react to capability states, not concrete
engine identity.

## Apple Reference And Diagnostics

Apple AV / AVFoundation / AVKit may be used for:

- metadata investigation
- subjective visual comparison
- HDR/EDR behavior observation
- platform capability research
- diagnostics or lab surfaces
- future Apple-native media research

These paths do not own production playback sessions, do not define current
fallback behavior, and do not create UI product branches.

## Future Apple AV Production Gate

Future Apple AV production playback requires a new explicit architecture
decision before implementation is treated as intended production direction.

That decision must define:

- supported media profiles and source types
- capability boundaries against mpv
- remote I/O and credential ownership
- subtitle, audio-track, timeline, frame-step, HDR/EDR, and immersive behavior
- fallback and teardown rules
- tests and device evidence
- updates to `ARCHITECTURE.md`, `docs/product_philosophy.md`,
  `docs/ubiquitous_language.md`, this contract, and relevant skill references

Future support for Dolby Vision, Apple-native immersive media, Spatial Video,
MV-HEVC, APMP, or other system media capabilities belongs behind this gate.

## Current Implementation Drift

Current code may contain diagnostic switches, Apple reference surfaces,
historical experiments, or temporary structure.

If code conflicts with the mpv-first route, treat it as implementation state to
understand and evaluate. Do not expand a dual-engine production theory to make
the existing code look intentional.

## Future Implementation Acceptance

Current implementation must prove:

- media launch enters one mpv-owned production session or returns unsupported
- switching media tears down the previous session
- `PlayerUI` does not branch on concrete adapter type or diagnostic renderer
- HDR claims stay tied to evidence normalized into shared domain terms
- remote I/O stays owned by the mpv-capable production route unless a future
  decision changes the route
- Apple reference playback remains diagnostic or research-only
