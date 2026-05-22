# Playback Engine Routing Contract

Status: Active normative contract.
Scope: Playback launch, backend adapter selection, session ownership, and UI-facing playback semantics.
This file is not product rationale, vocabulary, or a reference investigation.

## Summary

Enchron uses deterministic single-engine routing per playback session.

The long-term direction is **Apple-native first, mpv-safe fallback**. This
contract defines how a session selects one backend engine before playback
starts, and how shared playback semantics remain stable across engines.

This document is normative. Product rationale belongs in
`docs/product_philosophy.md`. Vocabulary belongs in
`docs/ubiquitous_language.md`. High-level module ownership belongs in
`ARCHITECTURE.md`.

## Engines

Supported route names:

- `mpv`
- `appleAV`

The route name is internal architecture vocabulary. `PlayerUI` must not expose
product behavior by branching on concrete engine identity.

## Router Inputs

The router may use:

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
- user override, only if future product direction explicitly supports it

Required session capabilities may include:

- needs frame output
- needs custom texture surface
- needs system player surface
- needs panorama projection
- needs stereoscopic projection
- needs reliable audio track selection
- needs reliable subtitle selection
- needs external subtitle support
- needs frame stepping
- needs HDR metadata evidence
- needs remote seek reliability

These are domain capability requirements. They are not UI-level engine branches.

## Router Output

The router returns a `PlaybackEngineRoute`.

A route contains:

- `selectedEngine`: `mpv`, `appleAV`, or `none`
- `reasonCode`: stable machine-testable reason
- `decisionBasis`: evidence used by the router
- `requiredCapabilities`: capabilities this route is expected to satisfy
- `fallbackPolicy`: `none` or `preStartOnly`
- `unsupportedReason`: present when `selectedEngine` is `none`

`reasonCode` should be stable enough for tests. Example reason codes:

- `appleNativeSource`
- `appleHLS`
- `photosAsset`
- `spatialVideo`
- `appleImmersiveMedia`
- `openFormatContainer`
- `complexSubtitleModel`
- `complexAudioTrackModel`
- `remoteIORequiresMPV`
- `unknownProjectionMetadata`
- `requiredCapabilityUnavailable`
- `unsupportedSource`

## Hard Session Contract

One playback session owns exactly one engine.

The selected route is decided before user-visible playback starts.

No parallel playback engines are allowed for one session.

No dual product state machine is allowed.

No session-time engine switching is allowed.

`PlayerUI` must not branch on concrete adapter type.

`PlaybackEngineRoute` is not `PlaybackMode`.

`PlaybackMode` remains a presentation decision: window, immersive scene, or
panorama.

## Launch Flow

Both direct playback and prepare/confirm playback must pass through the same
routing contract.

`PlaybackLaunchCoordinator.preparePlayback` may collect metadata and create a
route candidate, but must not start multiple engines.

A route candidate is valid only for the matching launch generation and source
fingerprint.

`confirmPlayback` must receive or recompute a valid route before actual playback
starts.

Placeholder metadata is not authoritative route evidence.

Persisted metadata, inferred metadata, prefetched metadata, and runtime-detected
metadata are not equivalent. The route must preserve evidence quality.

## Fallback

Same-engine retry is not cross-engine fallback.

Same-engine retry may occur inside the selected route when the session remains
owned by the same engine.

Cross-engine fallback is allowed only before user-visible playback starts, or
after a failed launch tears down the failed engine first.

After the first visible frame, audible playback, or user-visible playing state
is published, the session must not switch engines.

A later fatal engine failure ends the session. Retrying with another engine
starts a new playback session.

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

The UI must not branch on `MPVPlayerAdapter`, `AVPlayerAdapter`, `mpv`, or
`appleAV`.

## Frame Output

Frame output is a shared domain capability.

An adapter may report frame output available, unavailable because a system
surface owns rendering, or unsupported for the requested presentation path.

`PlayerUI` and `SpatialScene` must react to capability states, not concrete
engine identity.

## Apple Asset Loading

Unsupported Apple asset loading resolves to unsupported/error unless the
original source can be represented as an mpv-ownable source without breaking the
shared playback contract.

mpv fallback is safe only when mpv can own the original source.

## User Override

Future user override may only choose among engines that are eligible for the
source and required session capabilities.

User override must not become a UI-level adapter selection path.

## Future Implementation Acceptance

Future implementation must prove:

- MP4/MOV/M4V/HLS choose `appleAV` only when Apple-native evidence and required
  capabilities match.
- MKV/WebM/AVI/TS/M2TS/FLV choose `mpv` unless a future explicit product rule
  changes the eligibility model.
- Unknown container, unknown codec, unknown subtitle model, unknown HDR
  metadata, or insufficient Apple-native evidence does not automatically choose
  `appleAV`.
- One playback session owns one engine.
- Switching media tears down the previous session.
- `PlayerUI` does not branch on concrete adapter type.
- HDR claims stay tied to engine-specific evidence normalized into shared
  domain terms.
- Remote I/O defaults to the safest eligible route.
