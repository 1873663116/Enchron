---
{"actor":{"actorId":"checker:regression-review-stage","environmentDigest":"sha256:5946eb63656d919ac5527ceaa0b710e9be3ce5d8506fbcc169686de865a24ed4"},"issuedAt":"2026-08-30T12:59:31Z","packetDigest":"sha256:ae8c678a091107bcb41af53d3a84459eedf71c1c57ec42d5d071df3e5b9cabf0","packetId":"review-packet:deterministic-ae8c678a091107bc","reviewer":"deterministic","schema":"enchron.regression.review-report","schemaVersion":1,"usage":{"inputTokens":3286,"reviewItems":12}}
---

# Deterministic Catalog review

This report accepts `review-packet:deterministic-ae8c678a091107bc` (`sha256:ae8c678a091107bcb41af53d3a84459eedf71c1c57ec42d5d071df3e5b9cabf0`).

## Catalog-wide checks

- Catalog digest: `sha256:74af79464c37933b878cb5a97ad2d93555125f51dc3b0e1cb0e69dd54577e71d`
- Review plan digest: `sha256:4ccc23e4bc0462e90692d77513b8b59dbaa361110b9c193046881e49169e7c1e`
- Target Promises: `65`
- Selected Scenarios: `65`
- MainGate attempts: `simulator=scenario:local-media-lifecycle:clean-flat-playback-main-gate, device=scenario:local-media-lifecycle:clean-flat-playback-main-gate`
- Journey ordering edges involving a MainGate: `0`
- Verified Operation and Oracle locators: `46`

## Implementation locators

- `operation:accessibility.activate@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:accessibility.inspect@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:accessibility.type@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:app.relaunch@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:diagnostics.browse-hierarchy@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:diagnostics.playback-state@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:diagnostics.surface-probe@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:evidence.capture-audio@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:evidence.capture-frames@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:evidence.structural-test@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:format.apply@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:harness.assert-channels@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:harness.ensure-session@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:harness.reset-product-state@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:host.preflight@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:input.device-hub-pinch@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:input.device-hub-prepare@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:issue.present@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:library.snapshot@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:media.import-staged@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:media.open@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:media.stage-fixture@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:navigation.select-tab@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:playback.await-window-state@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:playback.seek@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:playback.select-subtitle@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:playback.wait-position@2` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:preparation.local-directory-subtitle-source@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:presentation.enter-docked-skybox@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:presentation.enter-panorama@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:presentation.exit-spatial@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:storage.clear@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:transition-trace.arm@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:transition-trace.disarm@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `operation:transition-trace.fetch@1` uses `Scripts/verification/regression_operation_adapter.py` at `sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56`
- `oracle:agent-audio@2` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:c6b70eab5f3d996720df6f989ecbdbab4a29574bd20391fb5840424935c25212`
- `oracle:agent-structured-accessibility-tree@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:c6b70eab5f3d996720df6f989ecbdbab4a29574bd20391fb5840424935c25212`
- `oracle:agent-structured-emby-evidence@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:c6b70eab5f3d996720df6f989ecbdbab4a29574bd20391fb5840424935c25212`
- `oracle:agent-structured-interaction-trace@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:c6b70eab5f3d996720df6f989ecbdbab4a29574bd20391fb5840424935c25212`
- `oracle:agent-structured-library-command@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:c6b70eab5f3d996720df6f989ecbdbab4a29574bd20391fb5840424935c25212`
- `oracle:agent-structured-playback-probe@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:c6b70eab5f3d996720df6f989ecbdbab4a29574bd20391fb5840424935c25212`
- `oracle:agent-structured-spatial-input@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:c6b70eab5f3d996720df6f989ecbdbab4a29574bd20391fb5840424935c25212`
- `oracle:agent-structured-structural-test@2` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:c6b70eab5f3d996720df6f989ecbdbab4a29574bd20391fb5840424935c25212`
- `oracle:agent-structured-transition@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:c6b70eab5f3d996720df6f989ecbdbab4a29574bd20391fb5840424935c25212`
- `oracle:agent-structured-window-control-plane@1` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:c6b70eab5f3d996720df6f989ecbdbab4a29574bd20391fb5840424935c25212`
- `oracle:agent-visual@2` uses `Scripts/verification/regression_oracle_adapter.py` at `sha256:c6b70eab5f3d996720df6f989ecbdbab4a29574bd20391fb5840424935c25212`

## Packet units

- `rubric:rubric:presentation-tour.automatic-source-provenance.o01@1` `sha256:5cf63c10fd39074cdb29a99174337575c650f8428fde502a4e0a394a56b7fa6a` from `Regression/rubrics/rubric-presentation-tour-automatic-source-provenance-o01-1.md`
- `rubric:rubric:presentation-tour.format-application-route.o01@1` `sha256:2b6d3f61a6aad4163cdeeac49f4fa826e8fe439ab78285fa7b83f86455233888` from `Regression/rubrics/rubric-presentation-tour-format-application-route-o01-1.md`
- `rubric:rubric:presentation-tour.format-editor-hosts-window-and-portal.o01@1` `sha256:7f4c3baffce29fec895d43e56b1e44f304c3b946d9ee5ffa91539c3ef98bfac9` from `Regression/rubrics/rubric-presentation-tour-format-editor-hosts-window-and-portal-o01-1.md`
- `rubric:rubric:presentation-tour.initial-presentation-routing.o01@1` `sha256:914710fccb70df548bc41558ca8843acd5a3977f29b43307769a5333ad27f4ce` from `Regression/rubrics/rubric-presentation-tour-initial-presentation-routing-o01-1.md`
- `rubric:rubric:presentation-tour.panorama-to-portal-exit.o01@1` `sha256:132d40a32901f45f090b371515480a95c523104d11901ca8a6ff44f6c2d67e3c` from `Regression/rubrics/rubric-presentation-tour-panorama-to-portal-exit-o01-1.md`
- `rubric:rubric:presentation-tour.portal-format-and-panorama-actions-coexist.o01@1` `sha256:f3369dff5bf14753582e133e3c96252b71b67390b536ed4d8fdf786625a4b983` from `Regression/rubrics/rubric-presentation-tour-portal-format-and-panorama-actions-coexist-o01-1.md`
- `rubric:rubric:presentation-tour.portal-to-panorama-explicit-entry.o01@1` `sha256:e23084648c331950c3113c5871ca28fb2f16557fc2d1dbe0d196cdd6b5229532` from `Regression/rubrics/rubric-presentation-tour-portal-to-panorama-explicit-entry-o01-1.md`
- `rubric:rubric:presentation-tour.spatial-controls-summon.o01@1` `sha256:b9e206e9d4b4e4a9796b7652fcbf73a684219a4beb59d6b0cce448d60bb69726` from `Regression/rubrics/rubric-presentation-tour-spatial-controls-summon-o01-1.md`
- `rubric:rubric:presentation-tour.track-selection-survives-seek-and-presentation.o01@1` `sha256:39646a0a41a59f81dac19d23b5192e85e2bfb6e5768cf4d7a8cd11ed154506b7` from `Regression/rubrics/rubric-presentation-tour-track-selection-survives-seek-and-presentation-o01-1.md`
- `rubric:rubric:presentation-tour.transition-timeout-rolls-back.o01@1` `sha256:d37611ccdd83ce2c34181c5cd69cd4062b9a94ee8365249c3310814a3a0286a7` from `Regression/rubrics/rubric-presentation-tour-transition-timeout-rolls-back-o01-1.md`
- `rubric:rubric:presentation-tour.window-docked-round-trip.o01@1` `sha256:cf087ccee93e16c1021684c0a293792b6d4b56cc72d5579739cfdd6387b2352d` from `Regression/rubrics/rubric-presentation-tour-window-docked-round-trip-o01-1.md`
- `rubric:rubric:presentation-tour.window-to-portal-format-route.o01@1` `sha256:eecb5b134277c83613249ae062a6fa8d05f3aa72aee08e5a54df1a7707d2432b` from `Regression/rubrics/rubric-presentation-tour-window-to-portal-format-route-o01-1.md`
