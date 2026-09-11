#!/usr/bin/env python3

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BASELINE = REPOSITORY_ROOT / "Config/playback_surface_structure_baseline.json"


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


def without_debug_blocks(source: str) -> str:
    lines: list[str] = []
    debug_depth = 0
    for line in source.splitlines(keepends=True):
        directive = line.strip()
        if directive == "#if DEBUG":
            debug_depth = 1
            continue
        if debug_depth:
            if directive.startswith("#if "):
                debug_depth += 1
            elif directive == "#endif":
                debug_depth -= 1
            continue
        lines.append(line)
    return "".join(lines)


VIOLATIONS: list[str] = []

RENDERER_ACQUISITION = "PlaybackVideoSurfaceReconciler.acquire("
HOST_ACTIVITY_ARGUMENT = "hostIsActive:"
BOOLEAN_LITERALS = ("true", "false")


def argument_list(source: str, opening: int) -> str:
    depth = 0
    for index in range(opening, len(source)):
        character = source[index]
        if character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return source[opening + 1:index]
    raise AssertionError("unterminated argument list at offset " + str(opening))


def host_activity_arguments(source: str) -> list[str]:
    arguments: list[str] = []
    position = source.find(RENDERER_ACQUISITION)
    while position >= 0:
        opening = position + len(RENDERER_ACQUISITION) - 1
        for argument in argument_list(source, opening).split(","):
            name, separator, value = argument.partition(":")
            if separator and name.strip() + ":" == HOST_ACTIVITY_ARGUMENT:
                arguments.append(value.strip())
        position = source.find(RENDERER_ACQUISITION, position + 1)
    return arguments


def check_every_host_reports_whether_it_still_hosts() -> None:
    """A host that hardcodes hostIsActive keeps passing the renderer's ownership
    check after its RealityView is gone, and the dying window's queued update
    claims the entity out from under the space that is opening. The two hosts
    that exist today are not the subject: any future third one is, so the rule
    reads every call site rather than the two it knows."""
    sites = 0
    for path in sorted((REPOSITORY_ROOT / "Modules").rglob("*.swift")):
        source = path.read_text(encoding="utf-8")
        if RENDERER_ACQUISITION not in source:
            continue
        for value in host_activity_arguments(source):
            sites += 1
            require(
                value not in BOOLEAN_LITERALS,
                str(path.relative_to(REPOSITORY_ROOT))
                + " claims the renderer with hostIsActive: "
                + value
                + "; a host has to report whether its RealityView still hosts it",
            )
    require(
        sites >= 2,
        "no playback surface host passes hostIsActive to the renderer "
        "acquisition; the check reads every call site and found none",
    )




def read_baseline(path: Path) -> Counter[str]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("version") != 1 or not isinstance(payload.get("knownGaps"), list):
        raise ValueError("expected version 1 with a knownGaps list")

    baseline: Counter[str] = Counter()
    for entry in payload["knownGaps"]:
        if not isinstance(entry, dict):
            raise ValueError("every knownGaps entry must be an object")
        name = entry.get("name")
        count = entry.get("count")
        if not isinstance(name, str) or not name.strip():
            raise ValueError("every known gap must have a non-empty name")
        if not isinstance(count, int) or isinstance(count, bool) or count < 1:
            raise ValueError(f"known gap {name!r} must have a positive integer count")
        if name in baseline:
            raise ValueError(f"known gap {name!r} is declared more than once")
        baseline[name] = count
    return baseline


def compare_with_baseline(
    violations: list[str],
    baseline: Counter[str],
) -> tuple[Counter[str], Counter[str]]:
    current = Counter(violations)
    return current - baseline, baseline - current


def occurrence_count(count: int) -> str:
    noun = "occurrence" if count == 1 else "occurrences"
    return f"{count} {noun}"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check playback UI and presentation source contracts."
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        default=DEFAULT_BASELINE,
        help="known-gap baseline JSON",
    )
    return parser.parse_args()


def require(condition: bool, message: str) -> None:
    """Records rather than raises, so one run names every drifted contract.

    Stopping at the first one costs a rerun per finding, and this file guards
    dozens of contracts across a codebase that moves. The exit status still
    fails; only the reporting is complete.
    """
    if not condition:
        VIOLATIONS.append(message)


def order(source: str, *markers: str) -> bool:
    """True when every marker appears, in the order given. A marker that is gone
    is a violation of the same contract as one that moved, so it answers False
    instead of raising and ending the run."""
    position = -1
    for marker in markers:
        found = source.find(marker, position + 1)
        if found < 0:
            return False
        position = found
    return True


def main() -> int:
    arguments = parse_arguments()
    VIOLATIONS.clear()
    surface = read("Modules/Playback/Views/PlaybackVideoSurface.swift")
    main_view = read("Apps/Enchron/MainView.swift")
    player_view = read("Apps/Enchron/PlayerView.swift")
    attachment_view = read(
        "Modules/Playback/Scenes/ImmersivePlaybackControlsAttachmentView.swift"
    )
    window_root = read(
        "Modules/Playback/Views/WindowPlaybackRootView.swift"
    )
    playback_panel = read(
        "Modules/Playback/Views/PlaybackPanel.swift"
    )
    geometry = read("Modules/Playback/Model/WindowPlaybackPageGeometry.swift")
    launch = read("Modules/Playback/PlaybackLaunchCoordinator.swift")
    runtime = read("Modules/Playback/PlaybackRuntime.swift")
    seek_policy = read(
        "Modules/Playback/Domain/PlaybackSeekPolicy.swift"
    )
    output_verification = read(
        "Modules/Playback/Domain/PlaybackOutputVerification.swift"
    )
    core_delivery = read(
        "Packages/PlaybackCore/Sources/PlaybackCore/SampleBufferPlaybackSession+Delivery.swift"
    )
    immersive = read("Modules/Playback/Scenes/ImmersiveSpaceView.swift")
    immersive_controls_attachment = read(
        "Modules/Playback/Scenes/ImmersivePlaybackControlsAttachment.swift"
    )
    head_pose_source = read("Modules/Playback/Scenes/HeadPoseSource.swift")
    reality_presenter = read(
        "Modules/Playback/Views/PlaybackRealityPresenter.swift"
    )
    surface_placement = read(
        "Modules/Playback/Model/PlaybackSurfacePlacement.swift"
    )
    playback_reality_adapter = read(
        "Modules/Playback/Platform/PlaybackSurfaceRealityKitAdapter.swift"
    )
    docked_pose_solver = read(
        "Modules/Playback/Platform/PlaybackDockedPoseSolver.swift"
    )
    spatial_handoff = read("Tests/EnchronAppUI/Spatial/SpatialHandoffUITests.swift")
    docked_placement = read("Tests/EnchronAppUI/Spatial/DockedPlacementUITests.swift")
    regression_support = read("Tests/EnchronAppUI/Support/DeviceRegressionSupport.swift")
    device_acceptance = read(
        "Tests/EnchronAppUI/VisionProDeviceAcceptanceUITests.swift"
    )
    app_scene = read("Apps/Enchron/EnchronApp.swift")
    application = read("Apps/Enchron/EnchronApplication.swift")
    architecture = read("ARCHITECTURE.md")
    environment_card_root = read(
        "Modules/Playback/Views/SenseZoneVolumeRoot.swift"
    )
    environment_components = read(
        "Modules/Playback/Views/EnvironmentComponents.swift"
    )
    presentation_model = read(
        "Modules/Playback/Model/PlaybackPresentation.swift"
    )
    session_model = read(
        "Modules/Playback/Session/PlaybackSessionModel.swift"
    )
    platform_executor_path = (
        REPOSITORY_ROOT
        / "Modules/Playback/Platform/SpatialPlatformEffectExecutor.swift"
    )
    platform_executor = platform_executor_path.read_text()
    execution_lease_path = (
        REPOSITORY_ROOT
        / "Modules/Playback/Platform/SpatialPlatformExecutionLease.swift"
    )
    require(
        execution_lease_path.exists(),
        "the App platform executor has no testable execution lease/generation seam",
    )
    execution_lease = execution_lease_path.read_text()

    window_playback = region(
        player_view,
        "private var windowPlayback: some View",
        "private var hostedPlaybackPresentation",
    )
    vision_surface = region(
        surface,
        "private var visionSurface: some View",
        "private func scheduleVisionSurfaceUpdate(",
    )
    spatial_controls = region(
        attachment_view,
        "struct ImmersivePlaybackControlsAttachmentView: View",
        "public enum PlaybackStateAccessibility",
    )

    require("PerspectiveCameraComponent(" in surface, "window camera is missing")
    check_every_host_reports_whether_it_still_hosts()
    window_interaction_surface = region(
        reality_presenter,
        "enum PlaybackWindowInteractionSurface",
        "enum PlaybackDockedInteractionSurface",
    )
    require(
        "entity.components.set(InputTargetComponent())" in window_interaction_surface
        and "CollisionComponent(shapes: [.generateBox(size: region.size)])"
        in window_interaction_surface
        and "entity.position = region.center" in window_interaction_surface
        and "WindowPlaybackSurfaceGeometry.interactionRegion(" in window_interaction_surface,
        "the window playback surface entity carries no viewer-facing collision input target",
    )
    require(
        "entity.components.remove(InputTargetComponent.self)" in window_interaction_surface
        and "entity.components.remove(CollisionComponent.self)" in window_interaction_surface,
        "the window playback surface never yields its hit target to presented chrome",
    )
    interaction_region = region(
        surface_placement,
        "nonisolated public static func interactionRegion(",
        "nonisolated public static func layout(",
    )
    require(
        "guard occlusion.secondaryMenuIsPresented" not in interaction_region
        and "resolvedSize.y * min(occlusion.topFraction / fill, 1)" in interaction_region
        and "resolvedSize.y * min(occlusion.bottomFraction / fill, 1)" in interaction_region
        and "size: [resolvedSize.x, height, thickness]" in interaction_region
        and "center: [0, (bottomOccluded - topOccluded) / 2, frontOffset]" in interaction_region,
        "the window interaction region must subtract both chrome strips from the video area and must not vanish for a presented menu",
    )
    require(
        "PlaybackWindowInteractionSurface.install(" in surface
        and "component?.playerScreenSize" in surface
        and "TapGesture()" in surface
        and ".targetedToEntity(playbackVideoEntityStore.windowInteractionSurface)"
        in surface
        and ".simultaneousGesture(surfaceTapGesture)" in vision_surface,
        "window surface taps are not recognized on the sized playback entity",
    )
    window_surface_content = region(
        window_root,
        "private var surfaceContent: some View",
        "private func updateWindowGeometry(",
    )
    require(
        "Button(" not in window_root
        and ".allowsHitTesting" not in vision_surface
        and "Color.clear" not in window_surface_content
        and ".allowsHitTesting" not in window_surface_content
        and order(
            window_surface_content,
            "videoContent",
            ".accessibilityElement(children: .contain)",
            '.accessibilityIdentifier("PlayerUI-window-playback-surface")',
        ),
        "the window video surface is not a RealityView whose accessibility"
        " container carries the surface identifier while the interaction"
        " entity carries the button",
    )
    require(
        reality_presenter.count("PlaybackSurfaceAccessibility.install(on: entity)") == 2
        and "PlaybackSurfaceAccessibility.install(on: panel)" in reality_presenter
        and "entity.components.remove(AccessibilityComponent.self)" in reality_presenter
        and "accessibility.traits = [.button]" in reality_presenter,
        "the playback surface button lives on the interaction colliders, not on"
        " the video entity",
    )
    require(
        "content.cameraTarget = presentation == .docked ? videoEntity : nil" in surface,
        "camera target does not follow presentation",
    )
    require(
        ".overlay(alignment: .top)" in window_root,
        "window chrome does not overlay video",
    )
    require(
        ".overlay(alignment: .bottomLeading)" in window_root,
        "window media facts do not overlay the video plane",
    )
    require("PlayerInfoBarView()" in window_playback, "window info bar is missing")
    require(
        "WindowPlayerDeckView(" in player_view,
        "window playback ornament is missing",
    )
    require(
        "WindowPlayerDeckView(" not in window_playback,
        "window playback controls are still inside the window content plane",
    )
    require(
        "attachmentAnchor: .scene(.bottom)" in player_view,
        "window playback controls are not attached as a bottom ornament",
    )
    require(
        "WindowPlaybackRootView(" in window_playback,
        "the App does not use the shared window playback root",
    )
    require(
        "playbackRuntime.displayMediaProfile?.resolution" in player_view
        and "playbackRuntime.effectiveStereoLayout" in player_view,
        "window playback geometry does not use the current displayed media dimensions",
    )
    require(
        "minimumWidth: CGFloat = 750" in window_root
        and "maximumExtent: CGFloat = 1_808" in window_root
        and "private func size(area: CGFloat) -> CGSize" in window_root,
        "window playback tiers are not derived from a target area",
    )
    require(
        "UIWindowScene.GeometryPreferences.Vision(" in window_root
        and "resizingRestrictions: .uniform" in window_root
        and "minimumSize: layout.minimumSize" in window_root
        and "maximumSize: layout.maximumSize" in window_root
        and "requestGeometryUpdate(preferences)" in window_root,
        "the shared window playback root does not own the system uniform resize contract",
    )
    require(
        "requestGeometryUpdate(" not in main_view
        and "requestGeometryUpdate(" not in player_view,
        "the production host duplicates the shared window playback resize contract",
    )
    design_tokens = read("Modules/DesignSystem/DesignTokens.swift")
    require(
        "enum PlaybackSurface" not in design_tokens
        and "interactionPlane" not in design_tokens
        and "interactionSurface" not in design_tokens,
        "DesignTokens still owns a painted input plane",
    )
    require(
        "panelChromeSize" in playback_panel
        and "PlayerPanelChrome.contentSize" in playback_panel
        and "case .windowOrnament:" in playback_panel
        and "ControlBar.contentWidth" in design_tokens,
        "the window ornament does not have a stable rendered outer width",
    )
    require(
        "WindowPlaybackPageLayout(" not in window_playback,
        "window playback still divides video and controls into separate layout regions",
    )
    require("VStack(spacing: DesignTokens.Spacing.md)" not in window_playback, "deck shrinks video canvas")
    require("attachments:" not in vision_surface, "vision window controls use a RealityView attachment")
    require("VisionWindowPlaybackControlPlane" not in surface, "duplicate vision window controls remain")
    require(
        vision_surface.count(
            ".frame(depth: WindowPlaybackSurfaceGeometry.flatDepth)"
        ) >= 2,
        "the RealityView and its 3D reader are not constrained to the window plane",
    )
    require(
        "PlaybackSurfacePlacement.window(" in surface
        and "sceneCenter: layout.sceneCenter" in surface
        and "sceneExtents: sceneBounds.extents" in surface,
        "window playback does not center and scale the video entity from the same RealityView bounds",
    )
    require(
        "struct RegressionStateSnapshot" in regression_support
        and 'split(separator: ";")' in regression_support
        and 'func string(_ key: String)' in regression_support
        and 'func uint64(_ key: String)' in regression_support
        and '$0.string("lifecycle")' in regression_support,
        "the device suites read the diagnostic value as one formatted string instead of named fields",
    )
    require(
        '"ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] =' in regression_support
        and '"ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"' in device_acceptance,
        "device UI acceptance races the unrelated production controls auto-hide timer",
    )
    require(
        '"PlayerUI-spatial-state"' in attachment_view
        and '"PlayerUI-spatial-state"' in spatial_handoff
        and '"PlayerUI-spatial-state"' in docked_placement
        and '"PlayerUI-spatial-control-plane"' not in attachment_view,
        "spatial acceptance state collapses or replaces the real Player Control Deck accessibility tree",
    )
    require(
        '"position=\\(position.seconds)"' in player_view
        and '"streamEpoch=\\(output.streamEpoch)"' in player_view
        and '"videoSamples=\\(output.videoSampleCount)"' in player_view
        and '"rendererInputs=\\(output.acceptedRendererInputCount)"' in player_view
        and '"displayedPixel=\\(output.displayedPixelBuffer)"' in player_view
        and '"audioSessionActive=\\(output.audioSessionActive)"' in player_view
        and '($0.double("position") ?? 0) >= baselinePosition' in regression_support
        and '($0.uint64("videoSamples") ?? 0) > baselineVideoSamples' in regression_support
        and '($0.uint64("rendererInputs") ?? 0) > baselineRendererInputs' in regression_support
        and '$0.bool("displayedPixel") == true' in regression_support
        and '$0.string("session") == baselineSession' in regression_support,
        "playback is called healthy without production output advancing under one unbroken session",
    )
    require(
        "requireHittable(" in regression_support
        and '["PlayerUI-TopAction-dock"].firstMatch.isHittable' in spatial_handoff
        and "exit.isHittable" in docked_placement,
        "the spatial suites accept a presentation whose controls never became usable",
    )
    require(
        "case .settled:" in runtime
        and "case .surfaceAttached:" in runtime
        and "guard presentation != .panorama else { return false }" in runtime
        and "case .ready, .paused, .ended:" in runtime
        and "testDockAndPanoramaRoundTripsInOneLaunch"
            in read("Tests/EnchronAppUI/VisionProDeviceAcceptanceUITests.swift"),
        "Panorama can commit without device settlement",
    )
    require(
        order(
            spatial_handoff,
            "guard requireHittable(exitSpatial",
            "settledTargetSnapshot,",
        )
        and "throw DeviceRegressionFailure.targetControlsUnavailable"
            in spatial_handoff,
        "spatial acceptance can operate stale UI before the presentation transaction settles",
    )
    require(
        "PlayerUI-window-playback-deck" not in window_playback,
        "window deck container overrides the identities of its child controls",
    )

    require("stopSpatialPlayback" in spatial_controls, "spatial stop action is missing")
    require(
        "await playbackLauncher.stopPlaybackAndWait(reason: .backButton)"
        in spatial_controls,
        "spatial stop does not await playback cleanup",
    )
    require(
        "requestStoppedPlaybackCleanup()" in spatial_controls,
        "spatial stop does not request owner-coordinated platform cleanup",
    )
    require(
        "SpatialPlatformEffectRequest" in presentation_model
        and "receiveSpatialPlatformResult" in presentation_model,
        "PlaybackPresentation does not own the pure platform request/result channel",
    )
    require(
        app_scene.count("SpatialPlatformEffectExecutor(") >= 3,
        "the live nonimmersive roots do not register platform action capability",
    )
    require(
        "SpatialPlatformEffectExecutor" not in environment_card_root,
        "the environment card volume competes for platform execution instead of"
        " presenting passively",
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
        and order(
            platform_executor,
            'leaseRegistry.claim(',
            'appModel.claimSpatialPlatformEffect(',
        ),
        "a pending effect can be claimed without a durable live-root execution lease",
    )
    require(
        "coordinator.register(" in platform_executor
        and "coordinator.unregister(" in platform_executor
        and "coordinator.requestDrain()" in platform_executor,
        "live roots do not register, unregister, and drain queued platform effects",
    )
    require(
        'Window("Environment", id: PlaybackSessionModel.senseZoneVolumeID)' in app_scene
        and "WindowGroup(id: AppModel.senseZoneVolumeID)" not in app_scene
        and ".windowStyle(.volumetric)" in app_scene,
        "Environment Card is not a singleton volumetric Window Scene",
    )
    require(
        'Window(\n            "Enchron",\n            id: "main"\n        )' in app_scene
        and "PlaybackWindowSceneIdentity" not in app_scene
        and "PlaybackWindowSceneIdentity" not in session_model,
        "Media Library is not a singleton Window Scene, so returning from "
        "playback can open a second one",
    )
    require(
        len(re.findall(r"(?<![A-Za-z])Window\(\n", app_scene)) == 1
        and 'id: "main"' in app_scene
        and '"Playback"' not in app_scene
        and "UIApplicationDelegateAdaptor" not in app_scene
        and "requestSceneSessionDestruction" not in app_scene,
        "the browser is no longer the app's single regular Window, so a second "
        "UIKit scene can reach the same Window and trap SwiftUI",
    )
    require(
        order(
            app_scene,
            'WindowGroup(\n            "Player",\n            id: SpatialPlatformWindowIdentity.player.rawValue\n        )',
            "WindowSceneGate(window: .player)",
            "PlayerView()",
            "SpatialPlatformEffectExecutor(windowIdentity: .player)",
            ".windowStyle(.plain)",
            ".windowResizability(.contentSize)",
            ".restorationBehavior(.disabled)",
            ".defaultLaunchBehavior(.suppressed)",
        ),
        "the player window is not a suppressed, unrestored WindowGroup with its "
        "own executor, so a relaunch from Home can build a bare player",
    )
    require(
        ".windowStyle(.plain)" in region(app_scene, 'id: "main"', "WindowGroup("),
        "the main window uses the system window style, whose glass cannot be "
        "dropped while video is visible, so playback needs its own window again",
    )
    require(
        "openWindow(id: SpatialPlatformWindowIdentity" not in platform_executor
        and "dismissWindow(id: SpatialPlatformWindowIdentity" not in platform_executor
        and "reconcilePlaybackWindowPresentation" not in platform_executor
        and "UIApplication.shared.openSessions" not in platform_executor,
        "the executor opens or dismisses a window by identity through openWindow; "
        "the browser is pushed over, never reopened, and the pushed windows are "
        "pushed and dismissed through the identity-routed capabilities",
    )
    require(
        order(
            platform_executor,
            "private func issuePushedWindow(",
            "let actions = capability(for: .main) else {",
            "actions.pushWindow(id: window.rawValue)",
            "private func issueDismissPushedWindow(",
            "let actions = capability(for: window) else {",
            "actions.dismissWindow(id: window.rawValue)",
        ),
        "a pushed window is pushed from a scene other than the browser or "
        "dismissed from a scene other than itself; pushing from a pushed window "
        "is not allowed and the browser would not come back in place",
    )
    require(
        "        case .enterImmersivePlayback:\n"
        "            [.openImmersiveSpace]\n"
        "                + (isPresent(playerWindowState) ? [.dismissPlayerWindow] : [])\n"
        in execution_lease
        and "normalizeWindowTransition" not in platform_executor.split(
            "private func enterImmersivePlayback("
        )[1].split("private func ")[1]
        and "ImmersiveResidentWindow" not in execution_lease
        and order(
            platform_executor,
            "private func performWindowTransition(",
            "let actions = SpatialPlatformPlaybackWindowPolicy.actions(",
            "for action in actions {",
        ),
        "entering an immersive presentation leaves the player window standing, so "
        "the window surface races the space for the freshly minted entity, or a "
        "failed entry normalizes by the residency, which has already moved to the "
        "space and will therefore refuse to push the player window back",
    )
    require(
        "playbackResidency: PlaybackResidency" in execution_lease
        and "playerWindowIsPresent" not in execution_lease
        and "case .immersiveSpace:\n            return" in platform_executor,
        "the browser's visibility follows the player window's presence rather "
        "than the playback residency, so the browser reappears the moment the "
        "player window is dismissed for the immersive space, or the residency "
        "observer pushes the player window back while the space is open",
    )
    require(
        order(
            platform_executor,
            "let windowRestorationBegan = await performWindowTransition(",
            "let playerWindowIsReady = await waitForPlayerWindowToBecomeForeground(",
            "connectedWindowScene(.player)?.activationState",
            "recordWindowResidency(.open, for: .player)",
            "preferPlayerWindowCapability()",
        ),
        "leaving the immersive space no longer waits for the player window to "
        "reach the foreground before rebinding",
    )
    require(
        order(
            platform_executor,
            "forName: UIScene.didDisconnectNotification,",
            "let playerWindowStateBeforeDisconnect = playerWindowState",
            "recordWindowResidency(.closed, for: window)",
            "guard window == .player else { return }",
            "SpatialPlatformPlayerWindowClosurePolicy.stopsPlayback(",
            "playerWindowStateBeforeDisconnect: playerWindowStateBeforeDisconnect",
            "onPlayerWindowClosedByWearer?()",
        )
        and order(
            application,
            "spatialPlatformEffectCoordinator.onPlayerWindowClosedByWearer = {",
            "launcher?.stopPlayback(reason: .windowClosedByWearer)",
        ),
        "closing the player window from the window bar no longer stops playback, "
        "or the app's own dismissal of it is read as a wearer close",
    )
    require(
        order(
            platform_executor,
            "private func dismissWindowAndWaitForDisappearance(",
            "if windowSceneHasDisconnected(window) {",
            "recordWindowResidency(.closed, for: window)",
        )
        and order(
            app_scene,
            "private struct WindowSceneGate<Content: View>: View {",
            ".windowSceneReporting { windowScene in",
            "spatialPlatformEffectCoordinator.recordWindowScene(windowScene, for: window)",
        ),
        "pushed window departure trusts the SwiftUI root's onDisappear, which "
        "visionOS delivers seconds after the UIKit scene is gone, so leaving the "
        "immersive space times out and reports a failed conversion",
    )
    require(
        "case playback" not in execution_lease
        and "    case main\n    case player\n}"
        in execution_lease
        and "Resident" not in app_scene,
        "the window identities are no longer the browser and the player, or a "
        "resident window scene is back",
    )
    require(
        "sceneRole" not in main_view
        and "Color.clear.enchronWindowGlassBackground" not in main_view
        and ".enchronWindowGlassBackground(.always)" in main_view
        and order(
            player_view,
            "enum PlayerWindowGlassPolicy {",
            "guard isRevealingPlayerWindow == false else { return false }",
            "        case .videoVisible:\n            return false",
            "        case .hidden, .placeholder:\n"
            "            return hasActiveSession == false",
            "        .enchronWindowGlassBackground(showsWindowGlass ? .always : .never)\n"
            "        .persistentSystemOverlays(\n"
            "            PlayerWindowSystemOverlayPolicy.visibility(\n"
            "                showsPlaybackChrome: showsPlaybackChrome\n"
            "            )\n"
            "        )",
        ),
        "the player window draws glass behind visible video, fills the gap between "
        "two video surfaces with grey, shows the system "
        "overlays while the playback controls are hidden, the browser drops its "
        "glass, the view splits by scene role again, or the glass sits on a "
        "background color whose platform view swallows the hit test of every "
        "pure SwiftUI control above it",
    )
    player_view_struct = region(
        player_view,
        "public struct PlayerView: View {",
        "private struct WindowControlPlaneStateModifier: ViewModifier {",
    )
    require(
        "playbackRuntime.playbackPosition" not in player_view_struct
        and "playbackRuntime.debugSnapshot()" not in player_view_struct
        and "windowPlaybackStateValue(" not in player_view_struct
        and ".modifier(windowControlPlaneState(geometryPolicy: geometryPolicy))" in player_view_struct
        and order(
            player_view,
            "private struct WindowControlPlaneStateModifier: ViewModifier {",
            "func body(content: Content) -> some View {",
            "content.accessibilityValue(stateValue)",
            "let position = playbackRuntime.playbackPosition",
        ),
        "the playback window's root body reads the playback position or the "
        "runtime debug snapshot, so every position update re-evaluates the whole "
        "window and UIKit rebuilds the presented menus",
    )
    require(
        order(
            session_model,
            "public func setControlsFocused(_ focused: Bool, at date: Date = Date()) {",
            "guard isControlsFocused != focused else { return }",
            "isControlsFocused = focused",
            "registerControlsInteraction(at: date)",
        ),
        "controls focus reporting rewrites the interaction timestamp on every "
        "menu appearance, so the playback window re-renders and re-presents "
        "the open submenu until it flickers",
    )
    require(
        'id: "playerControls"' not in app_scene
        and "PlayerControlsSceneIdentity" not in session_model
        and "ImmersivePlaybackControlsAttachmentView(" in immersive,
        "immersive playback controls still depend on a Window Scene",
    )
    exit_immersive_playback = region(
        platform_executor,
        "private func exitImmersivePlayback(",
        "private func swapWindowPlaybackProjection(",
    )
    immersive_disappearance = region(
        presentation_model,
        "case .immersiveSpaceDisappeared(let playbackContext):",
        "case .effectCompleted(let result):",
    )
    require(
        "presentationState.recordImmersiveSpaceDisappearance()"
        in immersive_disappearance
        and order(
            immersive_disappearance,
            'presentationState.recordImmersiveSpaceDisappearance()',
            'guard pendingSpatialPlatformEffect == nil',
        )
        and ".collapseImmersivePlayback(family)" in immersive_disappearance,
        "immersive disappearance records closure before queuing family collapse",
    )
    collapse_dispatch = region(
        platform_executor,
        "case .collapseImmersivePlayback(let family):",
        "case .swapWindowPlaybackProjection(let family):",
    )
    require(
        "await exitImmersivePlayback(" in collapse_dispatch
        and "mode: .alreadyClosedBySystem" in collapse_dispatch
        and "openImmersiveSpace" not in collapse_dispatch
        and "dismissImmersiveSpace" not in collapse_dispatch,
        "system collapse does not dispatch into the shared already-closed exit pipeline",
    )
    exit_mode = region(
        platform_executor,
        "private enum ImmersivePlaybackExitMode",
        "private enum ExecutionPhase",
    )
    require(
        "case .appRequested(let keepsEnvironmentOpen):" in exit_mode
        and "case .alreadyClosedBySystem:" in exit_mode
        and exit_mode.count("case .alreadyClosedBySystem:\n                false") == 2
        and "if mode.waitsForSourceFade" in exit_immersive_playback
        and "if mode.dismissesImmersiveSpace" in exit_immersive_playback
        and "openImmersiveSpace" not in exit_immersive_playback,
        "already-closed collapse can wait for source fade or issue immersive scene actions",
    )
    require(
        "ImmersivePlaybackControlsAttachmentPolicy.isVisible(" in attachment_view,
        "the controls attachment does not derive its visibility from the attachment policy",
    )
    require(
        ".allowsHitTesting(controlsAcceptInput)" in spatial_controls,
        "attached controls do not disable hit testing while inactive",
    )
    require(
        ".accessibilityHidden(controlsAcceptInput == false)" in spatial_controls,
        "attached controls remain accessibility-visible while inactive",
    )
    require(
        "HeadPoseSource" in immersive_controls_attachment,
        "attached controls do not take their placement from the shared head pose source",
    )
    require(
        "WorldTrackingProvider" in head_pose_source,
        "the shared head pose source does not use world tracking",
    )
    require(
        "queryDeviceAnchor(" in head_pose_source,
        "the shared head pose source does not query the device anchor",
    )
    require(
        "OpacityComponent(" in immersive_controls_attachment,
        "attached controls do not retain explicit RealityKit opacity",
    )
    require(
        "private func setEnabled(" in immersive_controls_attachment
        and "entity.isEnabled = value" in immersive_controls_attachment,
        "attached controls do not route RealityKit enablement through the instrumented writer",
    )
    require(
        'id: "playerControls"' not in platform_executor,
        "the platform executor retains the legacy playerControls Window Scene operation",
    )
    apply_locked_controls_transform = region(
        immersive_controls_attachment,
        "private func applyLockedTransform(",
        "private func hideAttachment(",
    )
    require(
        order(
            apply_locked_controls_transform,
            "entity.transform = transform",
            "OpacityComponent(opacity: 1)",
            "setEnabled(",
            "true,",
        )
        and 'writer: "ImmersivePlaybackControlsAttachmentController.applyLockedTransform"'
        in apply_locked_controls_transform,
        "immersive controls can become enabled before their locked transform applies",
    )
    pending_controls_placement = region(
        immersive_controls_attachment,
        "private func placeForPendingVisibilityRiseIfPossible()",
        "private func applyLockedTransform(",
    )
    require(
        "ImmersivePlaybackControlsPlacementGeometry.transform("
        in pending_controls_placement
        and "originFromAnchorTransform * offset" not in immersive_controls_attachment,
        "immersive controls placement copies head pitch and roll instead of yaw alone",
    )
    require(
        "immersiveControlsAttachment placementRequested" in immersive_controls_attachment
        and "immersiveControlsAttachment placementApplied revision="
        in pending_controls_placement
        and "reason=worldLocked" in pending_controls_placement,
        "immersive controls placement has no observable requested/applied/world-locked sequence",
    )
    require(
        "PortalPlaybackViewportRefreshPolicy.requiresRefresh(" in platform_executor
        and "portalPlaybackViewportRefreshState.request()" in platform_executor
        and "requestedRevision &+= 1" in execution_lease
        and "let viewportRefreshRevision = viewportRefreshRevision" in surface
        and "validVisionLayoutViewportRefreshRevision = viewportRefreshRevision" in surface
        and "recordMainWindowPlaybackSurfaceRefreshApplied" in player_view
        and "waitUntilPortalPlaybackViewportRefreshApplied(" in platform_executor,
        "the Portal collapse path does not invalidate a laid-out retained viewport",
    )
    require(
        "case .queueLatest:" in reality_presenter
        and "queuedOperation = operation" in reality_presenter
        and "case .startLatest:" in reality_presenter,
        "RealityView updates can still discard the Portal refresh while one is pending",
    )
    reality_view_id = region(
        immersive,
        "private func realityViewID(for presentation:",
        "private func detachSpatialSurface()",
    )
    require(
        "return realityViewHostIdentity.description" in reality_view_id
        and "ObjectIdentifier(videoEntity)" not in reality_view_id,
        "immersive RealityView identity is derived from the shared video Entity",
    )
    surface_reconciler = region(
        reality_presenter,
        "enum PlaybackVideoSurfaceReconciler",
        "public struct PlaybackRealityKitContentTypeScope",
    )
    require(
        order(
            surface_reconciler,
            "store.releaseDepartingEntity()",
            "PlaybackRealityViewTopologyWritePolicy.decision(",
            "runtime.claimRendererConsumer(",
        )
        and "presentation != .docked" not in surface_reconciler,
        "the shared surface reconciler no longer releases an in-place departing "
        "entity, gates the topology write and claims the renderer consumer in that "
        "order for every host",
    )
    require(
        "host: .mainWindow," in surface
        and "host: .immersiveSpace," in immersive
        and surface.count("PlaybackVideoSurfaceReconciler.acquire(") == 1
        and immersive.count("PlaybackVideoSurfaceReconciler.acquire(") == 1
        and "releaseDepartingEntity()" not in immersive
        and surface.count("releaseDepartingEntity()") == 1,
        "a host acquires the shared video entity outside the surface reconciler, "
        "or releases the departing entity on its own",
    )
    docked_interaction_surface = region(
        reality_presenter,
        "enum PlaybackDockedInteractionSurface",
        "enum PlaybackPanoramaInteractionSurface",
    )
    require(
        "let basis = simd_float3x3(pose.right, pose.up, pose.normal)"
        in playback_reality_adapter
        and "entity.setOrientation(simd_quatf(basis), relativeTo: nil)"
        in playback_reality_adapter
        and "entity.setPosition(pose.center, relativeTo: nil)"
        in playback_reality_adapter
        and "entity.look(" not in playback_reality_adapter
        and "let bottomEdge = SIMD3<Float>(0, restBottom, 0)" in docked_pose_solver
        and "let center = yaw.act(bottomEdge + halfHeight * planarUp)"
        in docked_pose_solver
        and "entity.position = [0, 0, frontOffset]"
        in docked_interaction_surface,
        "the Docked video plane takes its orientation from the solved bottom-edge basis and its interaction collider sits in front of it",
    )
    production_immersive = without_debug_blocks(immersive)
    require(
        "headInputProbe" not in production_immersive
        and "EnchronHeadInput.probe" not in production_immersive,
        "the diagnostic head-locked input plane ships in production",
    )
    require(
        'ProcessInfo.processInfo.environment["ENCHRON_HEAD_INPUT_PROBE"] == "1"'
        in immersive
        and 'ProcessInfo.processInfo.environment["ENCHRON_DOCKED_HIT_TEST_PROBES"] == "1"'
        in immersive,
        "immersive diagnostic colliders are not opt-in",
    )
    spatial_tap_gesture = region(
        immersive,
        "private var spatialSurfaceTapGesture:",
        "private func toggleControlsFromSpatialSurface(",
    )
    require(
        "PlaybackSurfaceInputOwnership.acceptsSpatialTapTarget(" in spatial_tap_gesture
        and "requestedPresentation != .docked" not in spatial_tap_gesture,
        "Panorama accepts spatial taps from entities outside its interaction shell",
    )
    spatial_input_ownership = region(
        reality_presenter,
        "enum PlaybackSurfaceInputOwnership",
        "enum PlaybackDockedInteractionSurface",
    )
    require(
        "case .windowInteractionSurface:" in spatial_input_ownership
        and "PlaybackWindowInteractionSurface.contains(entity)"
        in spatial_input_ownership
        and "case .dockedInteractionSurface:" in spatial_input_ownership
        and "PlaybackDockedInteractionSurface.contains(entity)"
        in spatial_input_ownership
        and "case .panoramaInteractionSurface:" in spatial_input_ownership
        and "PlaybackPanoramaInteractionSurface.contains(entity)"
        in spatial_input_ownership,
        "immersive spatial tap ownership is not symmetric by presentation",
    )
    docked_contains = region(
        docked_interaction_surface,
        "static func contains(_ entity: Entity)",
        "\n    }\n}",
    )
    require(
        "entity.name == entityName" in docked_contains
        and "anchorFrontProbeName" not in docked_contains
        and "childFrontProbeName" not in docked_contains,
        "Docked diagnostic probes can trigger production controls",
    )
    sub_perceptual_paint = re.compile(r"\.opacity\(\s*0\.0(?:0\d+|1\d?)\s*\)")
    for sub_perceptual_path in (
        "Modules/Playback/Views/PlaybackVideoSurface.swift",
        "Modules/Playback/Views/PlaybackPanel.swift",
        "Modules/Playback/Views/WindowPlaybackRootView.swift",
        "Modules/Playback/Views/WindowPlayerDeck.swift",
        "Modules/Playback/Scenes/ImmersivePlaybackControlsAttachmentView.swift",
        "Apps/Enchron/MainView.swift",
        "Modules/DesignSystem/DesignTokens.swift",
    ):
        production_paint_text = without_debug_blocks(read(sub_perceptual_path))
        for paint in sub_perceptual_paint.finditer(production_paint_text):
            require(
                ".allowsHitTesting(false)"
                in production_paint_text[paint.end():paint.end() + 240],
                f"{sub_perceptual_path} paints a sub-perceptual layer that can carry input",
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
        "private func enterImmersivePlayback(",
    )
    require(
        "executePlaybackTransport(beforeEffect, execution: execution)"
        in execute_region
        and order(
            execute_region,
            'executePlaybackTransport(beforeEffect, execution: execution)',
            'switch execution.request.effect',
        ),
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
        "setSpatialPlatformEffectReplacementHandler" in session_model
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
        and "updateActiveSessionID(sessionResource.sessionID)" in runtime
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
        "PlaybackSeekPolicy.intent(" in runtime
        and "startsPaused:" not in region(
            runtime,
            "public func seek(",
            "public func setSpeed(",
        )
        and "case .progressBar, .skip:" in seek_policy
        and "case .precisionTimeline, .frameStep:" in seek_policy,
        "seek controls bypass the event-by-lifecycle intent matrix",
    )
    require(
        "let requiresImmediateDecoderBootstrap = bootstrapIncomplete" in core_delivery
        and "if isPrerolling, bootstrap.complete, targetReached" in core_delivery
        and "synchronizer.setRate(timelineStartRate, time: activationTime)"
        in core_delivery,
        "decoder bootstrap can deadlock before the crossing sample reaches the renderer",
    )
    require(
        runtime.count("presentationState = .videoVisible") == 1
        and "phase == .settled && displayedPixelBuffer == true" in runtime
        and "productLifecycle == .ended" in runtime
        and "PlaybackOutputVerification.firstIncompleteBoundary" in player_view
        and "case displayedVideo" in output_verification
        and "case decoderBootstrap" in output_verification
        and "case timelineRate" in output_verification
        and "case audioSession" in output_verification
        and "case timelineAdvancement" in output_verification,
        "App presentation success has no displayed-pixel and continuous-output diagnostic gate",
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
        order(
            session_invalidation,
            'invalidateActiveExecution()',
            '.mediaSessionInvalidated(',
            'requestDrain()',
        ),
        "session invalidation does not invalidate A before owner cleanup and prompt drain",
    )
    session_cleanup = region(
        platform_executor,
        "private func normalizeInvalidatedSpatialPlayback",
        "private func enterImmersivePlayback(",
    )
    require(
        order(
            session_cleanup,
            'waitForImmersiveActionLane',
            'openWindow(id: "main"',
            'dismissImmersiveSpace(execution: execution)',
            'complete(execution',
        ),
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
    enter_immersive_playback = region(
        platform_executor,
        "private func enterImmersivePlayback(",
        "private func exitImmersivePlayback(",
    )
    require(
        "openDisposition != .preexisting" in enter_immersive_playback
        and "dismissImmersiveSpace(execution: execution)" in enter_immersive_playback,
        "spatial presentation failure does not distinguish pre-existing from request-opened space",
    )
    require(
        order(
            enter_immersive_playback,
            'prepareTechnicalSessionForPresentationConversion()',
            'activatePreparedTechnicalSessionReplacement()',
            'appModel.allowPresentationTargetRendererBinding()',
            'rebaseActivatedTechnicalSessionReplacement(',
            'restoreTargetPlaybackIntentBeforeSettlement(execution)',
            'waitUntilPresentationSettled(',
        ),
        "immersive entry replacement order is not prepare, activate, target binding, rebase, restore, settle",
    )
    require(
        order(
            enter_immersive_playback,
            'releaseDepartingPresentationResources()',
            'complete(execution',
        ),
        "immersive entry can commit before releasing its departing RealityKit component",
    )
    require(
        order(
            exit_immersive_playback,
            'prepareTechnicalSessionForPresentationConversion()',
            'openWindowAndWaitForAppearance(',
            'appModel.allowPresentationSourceRendererRelease()',
            'detachPlaybackSurface(',
            'waitUntilRendererConsumerIsReleased(',
            'activatePreparedTechnicalSessionReplacement()',
            'appModel.allowPresentationTargetRendererBinding()',
            'rebaseActivatedTechnicalSessionReplacement(',
            'restoreTargetPlaybackIntentBeforeSettlement(execution)',
            'waitUntilPresentationSettled(',
            'orderWindowToFront(',
            'releaseDepartingPresentationResources()',
            'complete(execution',
        ),
        "immersive exit omits or reorders the shared technical-session conversion sequence",
    )
    require(
        order(
            exit_immersive_playback,
            'releaseDepartingPresentationResources()',
            'complete(execution',
        ),
        "immersive exit can commit before releasing its departing RealityKit component",
    )
    projection_swap = region(
        platform_executor,
        "private func swapWindowPlaybackProjection(",
        "private func presentEnvironmentPreview(",
    )
    require(
        order(
            projection_swap,
            'prepareTechnicalSessionForPresentationConversion()',
            'activatePreparedTechnicalSessionReplacement()',
            'rebaseActivatedTechnicalSessionReplacement(',
            'restoreTargetPlaybackIntentBeforeSettlement(execution)',
            'waitUntilPresentationSettled(',
            'releaseDepartingPresentationResources()',
            'complete(execution',
        ),
        "main-window projection swap does not settle before releasing and retiring its source",
    )
    departing_release = region(
        platform_executor,
        "private func releaseDepartingPresentationResources()",
        "private func presentEnvironmentPreview(",
    )
    require(
        order(
            departing_release,
            'playbackVideoEntityStore.releaseDepartingEntity()',
            'retireDepartingTechnicalSessionAfterSceneDisappearance()',
        ),
        "renderer retirement can wait on a RealityKit component that still owns its target",
    )
    completion = region(
        platform_executor,
        "private func complete(",
        "\n}\n\n@MainActor\npublic struct SpatialPlatformEffectExecutor",
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
    guarded_marker = "private func executionIsLive("
    settlement_marker = "private func complete("
    require(
        platform_executor.count(guarded_marker) == 1
        and platform_executor.count(settlement_marker) == 1,
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
            order(body, "executionIsLive", action_token),
            f"{action_token} is not immediately protected by the execution lease",
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
        "private func setRuntimeIssue(",
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
        require(
            order(body, "executionIsLive", "await ", "executionIsLive"),
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
        order(
            open_immersive,
            'platformImmersiveSpaceResidency',
            'execution.actions.openImmersiveSpace',
        ),
        "immersive residency is not re-read inside the serialized lane before open",
    )
    require(
        order(
            open_immersive,
            "execution.actions.openImmersiveSpace",
            "platformImmersiveSpaceResidency = .open",
        )
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
        REPOSITORY_ROOT / "Modules/Playback",
    )
    debug_blackout_probe_platform_api_lines = {
        (
            "Modules/Playback/Scenes/ImmersiveSpaceView.swift",
            "@Environment(\\.openWindow)",
            "@Environment(\\.openWindow) private var openWindow",
        ),
        (
            "Modules/Playback/Scenes/ImmersiveSpaceView.swift",
            "@Environment(\\.dismissWindow)",
            "@Environment(\\.dismissWindow) private var dismissWindow",
        ),
        (
            "Modules/Playback/Scenes/ImmersiveSpaceView.swift",
            "openWindow(id:",
            'openWindow(id: "blackoutProbe")',
        ),
        (
            "Modules/Playback/Scenes/ImmersiveSpaceView.swift",
            "dismissWindow(id:",
            'dismissWindow(id: "blackoutProbe")',
        ),
    }
    for root in platform_roots:
        for source_path in root.rglob("*.swift"):
            if source_path == platform_executor_path:
                continue
            relative_path = str(source_path.relative_to(REPOSITORY_ROOT))
            for line in source_path.read_text().splitlines():
                stripped_line = line.strip()
                for token in platform_api_tokens:
                    if token not in line:
                        continue
                    require(
                        (relative_path, token, stripped_line)
                        in debug_blackout_probe_platform_api_lines,
                        f"{relative_path} bypasses the platform executor: {stripped_line}",
                    )
    require(
        "public func stopPlaybackAndWait(reason: PlaybackLeaveReason) async" in launch,
        "launch coordinator lacks cleanup barrier",
    )
    require(
        "public func leavePlaybackAndWait(reason: PlaybackLeaveReason) async" in runtime,
        "runtime lacks cleanup barrier",
    )
    require(
        "releaseInteractionSurfacesForRealityViewTransfer()" in immersive
        and "func releaseInteractionSurfacesForRealityViewTransfer()" in reality_presenter
        and "departingEntity?.components.remove(VideoPlayerComponent.self)" in reality_presenter,
        "immersive teardown drops the departing frame before the space closes",
    )
    require("presentationObservation.cancel()" in immersive, "immersive teardown leaves observation active")
    require("releaseRendererConsumer(" in immersive, "immersive teardown leaves renderer ownership active")

    try:
        baseline = read_baseline(arguments.baseline)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"playback surface baseline is invalid: {error}", file=sys.stderr)
        return 2

    new_gaps, resolved_gaps = compare_with_baseline(VIOLATIONS, baseline)
    if new_gaps:
        print("Playback surface structure found gaps outside the baseline:")
        for name, count in sorted(new_gaps.items()):
            print(f"  {name} ({occurrence_count(count)} beyond baseline)")
        if resolved_gaps:
            print("Playback surface baseline also has resolved entries; update it:")
            for name, count in sorted(resolved_gaps.items()):
                print(f"  {name} ({occurrence_count(count)} resolved)")
        return 1

    if resolved_gaps:
        print("Playback surface structure passed with resolved baseline entries:")
        for name, count in sorted(resolved_gaps.items()):
            print(f"  remove {occurrence_count(count)}: {name}")
        print(
            f"  {occurrence_count(len(VIOLATIONS))} of known gaps remain; "
            "update the baseline"
        )
        return 0

    print(
        "Playback surface structure passed: "
        f"{occurrence_count(len(VIOLATIONS))} of known gaps match the baseline"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
