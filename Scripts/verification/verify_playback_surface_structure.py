#!/usr/bin/env python3

from pathlib import Path
import re


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (REPOSITORY_ROOT / path).read_text()


def region(source: str, start_marker: str, end_marker: str) -> str:
    start = source.find(start_marker)
    if start < 0:
        raise AssertionError(f"missing source region: {start_marker}")
    end = source.find(end_marker, start + len(start_marker))
    if end < 0:
        raise AssertionError(f"missing source region terminator: {end_marker}")
    return source[start:end]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    surface = read("Modules/PlaybackPresentation/Views/PlaybackVideoSurface.swift")
    main_view = read("Apps/Enchron/MainView.swift")
    geometry = read("Modules/PlaybackPresentation/Model/WindowPlaybackPageGeometry.swift")
    launch = read("Modules/PlaybackFeature/PlaybackLaunchCoordinator.swift")
    runtime = read("Modules/PlaybackFeature/PlaybackRuntime.swift")
    immersive = read("Modules/PlaybackPresentation/Scenes/ImmersiveSpaceView.swift")
    spatial_acceptance = read(
        "Tests/EnchronAppUI/SpatialPresentationAcceptanceUITests.swift"
    )
    playback_deck_acceptance = read(
        "Tests/EnchronAppUI/PlaybackDeckUITests.swift"
    )
    spatial_verifier = read(
        "Scripts/verification/verify-spatial-presentations-simulator.zsh"
    )
    app_scene = read("Apps/Enchron/EnchronApp.swift")
    application = read("Apps/Enchron/EnchronApplication.swift")
    architecture = read("ARCHITECTURE.md")
    environment_card_root = read(
        "Modules/PlaybackPresentation/Views/SenseZoneVolumeRoot.swift"
    )
    environment_components = read(
        "Modules/PlaybackPresentation/Views/EnvironmentComponents.swift"
    )
    presentation_model = read(
        "Modules/PlaybackPresentation/Model/PlaybackPresentation.swift"
    )
    app_model = read("Apps/Enchron/AppModel.swift")
    platform_executor_path = (
        REPOSITORY_ROOT
        / "Modules/PlaybackPresentation/Platform/SpatialPlatformEffectExecutor.swift"
    )
    platform_executor = platform_executor_path.read_text()
    execution_lease_path = (
        REPOSITORY_ROOT
        / "Modules/PlaybackPresentation/Platform/SpatialPlatformExecutionLease.swift"
    )
    require(
        execution_lease_path.exists(),
        "the App platform executor has no testable execution lease/generation seam",
    )
    execution_lease = execution_lease_path.read_text()

    mac_surface = region(surface, "private var macOSSurface: some View", "#endif")
    window_playback = region(
        main_view,
        "private var windowPlayback: some View",
        "private var hostedPlaybackPresentation",
    )
    vision_surface = region(surface, "private var visionSurface: some View", "#else")
    spatial_controls = region(main_view, "struct SpatialPlaybackControlsRoot: View", "#endif")

    require("WindowPlaybackControlPlane()" not in mac_surface, "macOS surface owns duplicate controls")
    require(".task(id: presentation)" in mac_surface, "macOS surface does not track presentation")
    require(
        "guard presentation == .docked else { return }" in mac_surface,
        "macOS surface does not constrain the docking camera target",
    )
    require("PerspectiveCameraComponent(" in surface, "window camera is missing")
    require(
        "content.cameraTarget = presentation == .docked ? videoEntity : nil" in surface,
        "camera target does not follow presentation",
    )
    require(".overlay(alignment: .top)" in window_playback, "window chrome does not overlay video")
    require("PlayerInfoBarView()" in window_playback, "window info bar is missing")
    require("WindowPlayerDeckView()" in window_playback, "window deck is missing")
    require("WindowPlaybackPageLayout(" in window_playback, "shared window geometry is unused")
    require("VStack(spacing: DesignTokens.Spacing.md)" not in window_playback, "deck shrinks video canvas")
    require("nonisolated static func resolve(" in geometry, "window geometry is not independently callable")
    require("attachments:" not in vision_surface, "vision window controls use a RealityView attachment")
    require("VisionWindowPlaybackControlPlane" not in surface, "duplicate vision window controls remain")
    require(
        '"PlayerUI-window-control-plane"' in spatial_acceptance
        and "value CONTAINS[c] 'lifecycle=playing'" in spatial_acceptance
        and "value CONTAINS 'attached=window'" in spatial_acceptance
        and "value == 'playing'" not in spatial_acceptance,
        "spatial acceptance relies on a system-formatted accessibility value instead of structured playback facts",
    )
    require(
        '"ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"' in spatial_acceptance
        and '"ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"'
            in playback_deck_acceptance,
        "spatial UI acceptance races the unrelated production controls auto-hide timer",
    )
    require(
        '"PlayerUI-spatial-state"' in main_view
        and '"PlayerUI-spatial-state"' in spatial_acceptance
        and '"PlayerUI-spatial-control-plane"' not in main_view,
        "spatial acceptance state collapses or replaces the real Player Control Deck accessibility tree",
    )
    require(
        '"position=\\(position.seconds)"' in main_view
        and "verifySpatialPlaybackAdvances" in spatial_acceptance
        and "XCTAssertGreaterThan(" in spatial_acceptance
        and "first.pngRepresentation" not in spatial_acceptance,
        "spatial playback motion is inferred from unsupported Simulator screenshots instead of the real timeline",
    )
    require(
        "guard presentation != .panorama else { return false }" in runtime
        and "testPanoramaRequiresObservedVideoPlayerModesBeforeCommit"
            in read("Tests/EnchronMacOS/MacRealityPlaybackContractTests.swift"),
        "Panorama can commit before RealityKit reports its actual viewing modes as settled",
    )
    fixture_duration = re.search(r"^[ \t]*-t[ \t]+(\d+)", spatial_verifier, re.MULTILINE)
    require(
        fixture_duration is not None
        and int(fixture_duration.group(1)) >= 180,
        "the real-media spatial fixture can end before cold spatial round trips finish",
    )
    docked_state_gate = spatial_acceptance.index(
        "let dockedState = try waitForSpatialState("
    )
    docked_exit_gate = spatial_acceptance.index(
        '["PlayerPanel-button-exit-spatial"].firstMatch'
    )
    require(
        docked_state_gate < docked_exit_gate
        and "throw AcceptanceFailure.unmetCondition" in spatial_acceptance,
        "spatial acceptance can operate stale UI before the presentation transaction settles",
    )
    require(
        "PlayerUI-window-playback-deck" not in window_playback,
        "window deck container overrides the identities of its child controls",
    )

    require("stopSpatialPlayback" in spatial_controls, "spatial stop action is missing")
    require(
        "await playbackLauncher.stopPlaybackAndWait()" in spatial_controls,
        "spatial stop does not await playback cleanup",
    )
    require(
        "requestStoppedPlaybackCleanup()" in spatial_controls,
        "spatial stop does not request owner-coordinated platform cleanup",
    )
    stopped_cleanup = region(
        platform_executor,
        "case .normalizeStoppedSpatialPlayback",
        "private func presentSpatialPlayback(",
    )
    require(
        stopped_cleanup.index('openWindow(id: "main", execution: execution)')
        < stopped_cleanup.index('id: "playerControls",'),
        "spatial stop dismisses controls before reopening the library",
    )
    require(
        "SpatialPlatformEffectRequest" in presentation_model
        and "receiveSpatialPlatformResult" in presentation_model,
        "PlaybackPresentation does not own the pure platform request/result channel",
    )
    require(
        main_view.count("SpatialPlatformEffectExecutor()") >= 2
        and "SpatialPlatformEffectExecutor()" in environment_card_root,
        "the live nonimmersive roots do not register platform action capability",
    )
    require(
        "let spatialPlatformEffectCoordinator: SpatialPlatformEffectCoordinator"
        in application
        and ".environment(application.spatialPlatformEffectCoordinator)"
        in application,
        "the platform effect coordinator is not retained for the App lifetime",
    )
    require(
        "SpatialPlatformExecutionLeaseRegistry<SceneActions>" in platform_executor
        and "leaseRegistry.claim(" in platform_executor
        and platform_executor.index("leaseRegistry.claim(")
            < platform_executor.index("appModel.claimSpatialPlatformEffect("),
        "a pending effect can be claimed without a durable live-root execution lease",
    )
    require(
        "coordinator.register(" in platform_executor
        and "coordinator.unregister(" in platform_executor
        and "coordinator.requestDrain()" in platform_executor,
        "live roots do not register, unregister, and drain queued platform effects",
    )
    require(
        'Window("Environment", id: AppModel.senseZoneVolumeID)' in app_scene
        and "WindowGroup(id: AppModel.senseZoneVolumeID)" not in app_scene
        and ".windowStyle(.volumetric)" in app_scene,
        "Environment Card is not a singleton volumetric Window Scene",
    )
    require(
        ".environmentCardAppeared" in app_scene
        and ".environmentCardDisappeared" in app_scene,
        "Environment Card Scene lifecycle does not report residency facts to the owner",
    )
    require(
        "button-return" not in environment_components
        and "onReturn" not in environment_components
        and "requestEnvironmentCardPresented" not in environment_card_root,
        "Environment Card retains an App-owned Return/Back handshake",
    )
    execute_region = region(
        platform_executor,
        "private func execute(",
        "private func presentSpatialPlayback(",
    )
    require(
        "executePlaybackTransport(beforeEffect, execution: execution)"
        in execute_region
        and execute_region.index(
            "executePlaybackTransport(beforeEffect, execution: execution)"
        ) < execute_region.index("switch execution.request.effect"),
        "a platform effect can begin before the guarded media pause bridge succeeds",
    )
    require(
        "SpatialPlatformExecutionLease" in execution_lease
        and "isLive(" in execution_lease
        and "invalidateActiveExecution" in execution_lease,
        "platform execution has no live request/capability generation lease",
    )
    require(
        "isSpatialPlatformEffectCurrent" in platform_executor
        and "executionID: execution.lease.executionID" in platform_executor
        and "executionIsLive" in platform_executor
        and "activeSpatialPlatformExecutionID" in presentation_model,
        "the executor does not correlate its lease with the owner pending request",
    )
    require(
        "setSpatialPlatformEffectReplacementHandler" in app_model
        and "appModel.setSpatialPlatformEffectReplacementHandler" in platform_executor
        and "self?.requestDrain()" in platform_executor,
        "request replacement does not promptly invalidate and drain the active execution",
    )
    require(
        "enum SessionLifecycleEvent" in runtime
        and "setSessionLifecycleHandler" in runtime
        and len(
            re.findall(
                r"^[ \t]*activeSessionID[ \t]*=[ \t]*(?!=)",
                runtime,
                flags=re.MULTILINE,
            )
        ) == 1
        and "updateActiveSessionID(newSession.traceID)" in runtime
        and "updateActiveSessionID(nil)" in runtime
        and "playbackSessionLifecycleChanged" in platform_executor
        and "setSessionLifecycleHandler" in application,
        "Media Session invalidation has no direct PlaybackRuntime-to-coordinator lifecycle hook",
    )
    require(
        all(
            forbidden not in runtime + application
            for forbidden in (
                "isUITestFixture",
                "fixtureStartsEnded",
                "ui-test-fixture",
                "ENCHRON_UI_TEST_ENDED",
            )
        ),
        "production playback contains a test-only behavior path",
    )
    require(
        len(
            re.findall(
                r"^[ \t]*lifecycle[ \t]*=[ \t]*(?!=)",
                runtime,
                flags=re.MULTILINE,
            )
        ) == 1
        and "private func receive(_ status: PlaybackStatus)" in runtime
        and "lifecycle = status" in runtime
        and "renderer = AVSampleBufferVideoRenderer()" not in runtime
        and "ProcessInfo" not in runtime
        and application.count("PlaybackRuntime(") == 1
        and "let playbackRuntime = PlaybackRuntime()" in application,
        "PlaybackRuntime state can bypass PlaybackCore callbacks or production assembly",
    )
    require(
        "case mediaSessionInvalidated(" in presentation_model
        and "normalizeInvalidatedSpatialPlayback" in presentation_model
        and "didIssueVisibleSpatialSideEffect" in platform_executor,
        "session invalidation cannot enqueue owner-coordinated platform normalization",
    )
    lifecycle_handler = region(
        platform_executor,
        "static func invalidatedMediaSessionID",
        "func requestDrain()",
    )
    require(
        "case .replaced(let previousID, _), .ended(let previousID):"
        in lifecycle_handler
        and "case .activated:" in lifecycle_handler,
        "ended and replaced Media Sessions do not share the production invalidation path",
    )
    require(
        "根消失不会取消已经由 coordinator 认领的执行" not in architecture
        and "新的 `executionID` 重试" in architecture
        and "同时匹配当前 `requestID` 与 `executionID`" in architecture,
        "ARCHITECTURE still contradicts retryable execution-attempt identity",
    )
    session_invalidation = region(
        platform_executor,
        "private func invalidateExecutionForMediaSessionChange",
        "private func execute(",
    )
    require(
        session_invalidation.index("invalidateActiveExecution()")
        < session_invalidation.index(".mediaSessionInvalidated(")
        < session_invalidation.index("requestDrain()"),
        "session invalidation does not invalidate A before owner cleanup and prompt drain",
    )
    session_cleanup = region(
        platform_executor,
        "private func normalizeInvalidatedSpatialPlayback",
        "private func presentSpatialPlayback(",
    )
    require(
        session_cleanup.index("waitForImmersiveActionLane")
        < session_cleanup.index('openWindow(id: "main"')
        < session_cleanup.index("setFullImmersion(false")
        < session_cleanup.index("complete(execution"),
        "session cleanup is not serialized before normalizing Window and immersion",
    )
    require(
        "openImmersiveSpaceIfNeeded" in platform_executor
        and "appModel.immersiveSpaceResidency" in region(
            platform_executor,
            "private func openImmersiveSpaceIfNeeded",
            "private func dismissImmersiveSpace",
        ),
        "a capability retry can issue duplicate immersive open from a stale residency snapshot",
    )
    require(
        "SpatialPlatformImmersiveRequestProvenanceRegistry" in execution_lease
        and "immersiveRequestProvenance" in platform_executor
        and "recordOpenedSpace(" in platform_executor,
        "capability retries do not retain request-level immersive-space provenance",
    )
    present_spatial = region(
        platform_executor,
        "private func presentSpatialPlayback(",
        "private func recoverSpatialPlayback(",
    )
    require(
        "openDisposition == .preexisting" in present_spatial
        and "dismissImmersiveSpace(execution: execution)" in present_spatial,
        "spatial presentation failure does not distinguish pre-existing from request-opened space",
    )
    completion = region(
        platform_executor,
        "private func complete(",
        "\n}\n\n@MainActor\nstruct SpatialPlatformEffectExecutor",
    )
    require(
        "resolution != .ignored" in completion
        and "immersiveRequestProvenance.clear(requestID: execution.request.id)"
        in completion
        and "immersiveRequestProvenance.clear(" in session_invalidation,
        "immersive-space provenance is not cleared at request or session settlement",
    )
    require(
        "immersiveRequestProvenance.retainOnly(" in platform_executor
        and "requestID: pendingRequest?.id" in platform_executor
        and "mutating func retainOnly(requestID: UUID?)" in execution_lease,
        "abandoned request provenance can survive replacement without an active lease",
    )
    guarded_marker = "// MARK: - Guarded platform operations"
    settlement_marker = "// MARK: - Execution settlement"
    require(
        guarded_marker in platform_executor and settlement_marker in platform_executor,
        "the executor does not isolate guarded platform operations",
    )
    unguarded_execution = region(
        platform_executor,
        "private func execute(",
        guarded_marker,
    )
    for token in (
        "actions.openImmersiveSpace",
        "actions.dismissImmersiveSpace",
        "actions.openWindow",
        "actions.dismissWindow",
        "setPlatformPrefersFullImmersion",
        "playbackRuntime.detach()",
        "performSpatialPlaybackTransport(",
    ):
        require(
            token not in unguarded_execution,
            f"executor bypasses its live execution lease for {token}",
        )

    def require_action_guard(
        start_marker: str,
        end_marker: str,
        action_token: str,
    ) -> None:
        body = region(platform_executor, start_marker, end_marker)
        require(
            "executionIsLive" in body
            and body.index("executionIsLive") < body.index(action_token),
            f"{action_token} is not immediately protected by the execution lease",
        )

    require_action_guard(
        "private func setFullImmersion(",
        "private func openWindow(",
        "appModel.setPlatformPrefersFullImmersion",
    )
    require_action_guard(
        "private func openWindow(",
        "private func dismissWindow(",
        "execution.actions.openWindow",
    )
    require_action_guard(
        "private func dismissWindow(",
        "private func detachPlaybackSurface(",
        "execution.actions.dismissWindow",
    )
    require_action_guard(
        "private func detachPlaybackSurface(",
        "private func setRuntimeError(",
        "playbackRuntime.detach()",
    )
    require_action_guard(
        "private func executePlaybackTransport(",
        settlement_marker,
        "playbackRuntime.performSpatialPlaybackTransport",
    )

    def require_suspension_guards(
        start_marker: str,
        end_marker: str,
    ) -> None:
        body = region(platform_executor, start_marker, end_marker)
        suspension = body.index("await ")
        require(
            body.find("executionIsLive") >= 0
            and body.find("executionIsLive") < suspension
            and body.find("executionIsLive", suspension) > suspension,
            f"{start_marker} lacks liveness checks before and after suspension",
        )

    require_suspension_guards(
        "private func yieldExecution(",
        "private func openImmersiveSpaceIfNeeded(",
    )
    open_immersive = region(
        platform_executor,
        "private func openImmersiveSpaceIfNeeded(",
        "private func dismissImmersiveSpace(",
    )
    dismiss_immersive = region(
        platform_executor,
        "private func dismissImmersiveSpace(",
        "private func performSerializedImmersiveAction",
    )
    serialized_immersive = region(
        platform_executor,
        "private func performSerializedImmersiveAction",
        "private func waitUntilPresentationSettled(",
    )
    require(
        "performSerializedImmersiveAction(" in open_immersive
        and "guard executionIsLive(execution)" in open_immersive
        and "performSerializedImmersiveAction(" in dismiss_immersive
        and "return executionIsLive(execution)" in dismiss_immersive,
        "immersive scene actions do not revalidate after the serialized action lane",
    )
    require(
        open_immersive.index("platformImmersiveSpaceResidency")
        < open_immersive.index("execution.actions.openImmersiveSpace"),
        "immersive residency is not re-read inside the serialized lane before open",
    )
    open_action = open_immersive.index("execution.actions.openImmersiveSpace")
    require(
        "platformImmersiveSpaceResidency = .open"
            in open_immersive[open_action:]
        and app_scene.count("recordImmersiveSpaceResidency(") == 2,
        "immersive action and Scene lifecycle facts do not refresh retry residency",
    )
    require(
        "immersiveActionLane.perform(" in serialized_immersive
        and "guard executionIsLive(execution)" in serialized_immersive,
        "the executor does not revalidate after leaving the serialized action lane",
    )
    serialized_action_lane = execution_lease[
        execution_lease.index("final class SpatialPlatformSerializedActionLane") :
    ]
    predecessor_await = serialized_action_lane.index("await predecessor.value")
    operation_await = serialized_action_lane.index("let result = await operation()")
    tail_await = serialized_action_lane.index(
        "let result = await operationTask.value"
    )
    require(
        "isLive()" in serialized_action_lane[:predecessor_await]
        and "isLive()" in serialized_action_lane[
            predecessor_await:operation_await
        ]
        and "isLive()" in serialized_action_lane[operation_await:tail_await]
        and "isLive()" in serialized_action_lane[tail_await:],
        "the serialized immersive action lane lacks liveness checks around a suspension",
    )
    require_suspension_guards(
        "private func waitUntilPresentationSettled(",
        "private func waitUntilRendererConsumerIsReleased(",
    )
    require_suspension_guards(
        "private func waitUntilRendererConsumerIsReleased(",
        "private func executePlaybackTransport(",
    )
    platform_api_tokens = (
        "@Environment(\\.openImmersiveSpace)",
        "@Environment(\\.dismissImmersiveSpace)",
        "@Environment(\\.openWindow)",
        "@Environment(\\.dismissWindow)",
        "openImmersiveSpace(id:",
        "dismissImmersiveSpace()",
        "openWindow(id:",
        "dismissWindow(id:",
    )
    platform_roots = (
        REPOSITORY_ROOT / "Apps/Enchron",
        REPOSITORY_ROOT / "Modules/PlaybackPresentation",
    )
    for root in platform_roots:
        for source_path in root.rglob("*.swift"):
            if source_path == platform_executor_path:
                continue
            source = source_path.read_text()
            for token in platform_api_tokens:
                require(
                    token not in source,
                    f"{source_path.relative_to(REPOSITORY_ROOT)} bypasses the platform executor",
                )
    require("public func stopPlaybackAndWait() async" in launch, "launch coordinator lacks cleanup barrier")
    require("public func stopAndWait(" in runtime, "runtime lacks cleanup barrier")
    require(
        "videoEntity.components.remove(VideoPlayerComponent.self)" in immersive,
        "immersive teardown leaves the video component attached",
    )
    require("presentationObservation.cancel()" in immersive, "immersive teardown leaves observation active")
    require("releaseRendererConsumer(" in immersive, "immersive teardown leaves renderer ownership active")

    print("Playback surface structure constraints passed")


if __name__ == "__main__":
    main()
