---
{"actor":{"actorId":"checker:regression-review-stage","environmentDigest":"sha256:3675b32b39b3d33039cb175376a3458f7e324d4ebd1a0c6316b949ef76f44beb"},"issuedAt":"2026-08-29T14:25:15Z","packetDigest":"sha256:aaffe32699f441580a4b0dfae6aec659c39cad39409fd01f7abca7d7b802e8e4","packetId":"review-packet:deterministic-aaffe32699f44158","reviewer":"deterministic","schema":"enchron.regression.review-report","schemaVersion":1,"usage":{"inputTokens":5367,"reviewItems":4}}
---

# Deterministic Catalog review

This report accepts `review-packet:deterministic-aaffe32699f44158` (`sha256:aaffe32699f441580a4b0dfae6aec659c39cad39409fd01f7abca7d7b802e8e4`).

## Catalog-wide checks

- Catalog digest: `sha256:efc361ed553dbf2760d0ccbba7c5f5e39c20b120fd76cf4a20d34ce113ab4031`
- Review plan digest: `sha256:600429c9438dc23d50d119ac85a6fee6dd84d34d574efc2294b52fef734d08c3`
- Target Promises: `65`
- Selected Scenarios: `65`
- MainGate attempts: `simulator=scenario:local-media-lifecycle:clean-flat-playback-main-gate, device=scenario:local-media-lifecycle:clean-flat-playback-main-gate`
- Journey ordering edges involving a MainGate: `0`
- Verified Operation and Oracle locators: `46`

## Implementation locators

- `operation:accessibility.activate@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:accessibility.inspect@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:accessibility.type@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:app.relaunch@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:diagnostics.browse-hierarchy@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:diagnostics.playback-state@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:diagnostics.surface-probe@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:evidence.capture-audio@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:evidence.capture-frames@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:evidence.structural-test@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:format.apply@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:harness.assert-channels@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:harness.ensure-session@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:harness.reset-product-state@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:host.preflight@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:input.device-hub-pinch@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:input.device-hub-prepare@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:issue.present@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:library.snapshot@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:media.import-staged@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:media.open@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:media.stage-fixture@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:navigation.select-tab@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:playback.await-window-state@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:playback.seek@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:playback.select-subtitle@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:playback.wait-position@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:preparation.local-directory-subtitle-source@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:presentation.enter-docked-skybox@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:presentation.enter-panorama@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:presentation.exit-spatial@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:storage.clear@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:transition-trace.arm@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:transition-trace.disarm@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `operation:transition-trace.fetch@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:7e53f393ef9bd5d549b126c3223be5b993d9ca78ae86d57916da332f126032dc`
- `oracle:agent-audio@2` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686`
- `oracle:agent-structured-accessibility-tree@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686`
- `oracle:agent-structured-emby-range-log@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686`
- `oracle:agent-structured-interaction-trace@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686`
- `oracle:agent-structured-library-command@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686`
- `oracle:agent-structured-playback-probe@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686`
- `oracle:agent-structured-spatial-input@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686`
- `oracle:agent-structured-structural-test@2` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686`
- `oracle:agent-structured-transition@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686`
- `oracle:agent-structured-window-control-plane@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686`
- `oracle:agent-visual@2` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:b54222f6b388ccaf9c670c6228efa42ccec52bfe294a99527a5a7ec893208686`

## Packet units

- `journey:journey:projection-and-stereo` `sha256:7610bb8805a03fbc7f3a66af84faab6bd0951d80a7a42c6a38b51312fec30c2e` from `Regression/journeys/projection-and-stereo/journey.md`
- `scenario:scenario:projection-and-stereo:apple-immersive-projection` `sha256:1d38bb5de3ebe3a706bd811ec4880e07c233020d1d1d40e0009a8b7338a64efd` from `Regression/journeys/projection-and-stereo/scenarios/apple-immersive-projection.md`
- `scenario:scenario:projection-and-stereo:panorama-coverage-angle` `sha256:c26343eb5349730de859772fb16af1e3fbf5ccb1dfa351384c3212b1527aeb58` from `Regression/journeys/projection-and-stereo/scenarios/panorama-coverage-angle.md`
- `scenario:scenario:projection-and-stereo:stereo-view-separation` `sha256:e121accf23c4a3a0419d5bb481cf919a96280d41b891a9d636de6f670bbc8512` from `Regression/journeys/projection-and-stereo/scenarios/stereo-view-separation.md`
