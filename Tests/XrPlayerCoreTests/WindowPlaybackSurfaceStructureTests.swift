import Foundation
import Testing

@Suite("Window playback surface structure")
struct WindowPlaybackSurfaceStructureTests {
    @Test("Window overlays the transport deck without shrinking the RealityKit canvas")
    func deckOverlaysRealityKitCanvasOnBothPlatforms() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let surfaceSource = try String(
            contentsOf: repositoryRoot
                .appending(path: "XrPlayer/PlayerUI/Views/PlaybackVideoSurface.swift"),
            encoding: .utf8
        )
        let mainViewSource = try String(
            contentsOf: repositoryRoot.appending(path: "XrPlayer/MainView.swift"),
            encoding: .utf8
        )
        let geometrySource = try String(
            contentsOf: repositoryRoot.appending(
                path: "XrPlayer/PlayerUI/Domain/WindowPlaybackPageGeometry.swift"
            ),
            encoding: .utf8
        )
        let projectSource = try String(
            contentsOf: repositoryRoot.appending(path: "XrPlayer.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        let macOSSurface = try sourceRegion(
            named: "private var macOSSurface: some View",
            endingAt: "#endif",
            in: surfaceSource
        )
        let windowPlayback = try sourceRegion(
            named: "private var windowPlayback: some View",
            endingAt: "private var hostedPlaybackPresentation",
            in: mainViewSource
        )
        let enchronMacOSMembership = try sourceRegion(
            named: "Exceptions for \"XrPlayer\" folder in \"EnchronMacOS\" target",
            endingAt: "target = D40000032FA0000100E1C001",
            in: projectSource
        )

        #expect(macOSSurface.contains("WindowPlaybackControlPlane()") == false)
        #expect(macOSSurface.contains(".task(id: presentation)"))
        #expect(macOSSurface.contains("guard presentation == .docked else { return }"))
        #expect(surfaceSource.contains("PerspectiveCameraComponent("))
        #expect(
            surfaceSource.contains(
                "content.cameraTarget = presentation == .docked ? videoEntity : nil"
            )
        )
        #expect(windowPlayback.contains(".overlay(alignment: .top)"))
        #expect(windowPlayback.contains("PlayerInfoBarView()"))
        #expect(windowPlayback.contains("WindowPlayerDeckView()"))
        #expect(windowPlayback.contains("WindowPlaybackPageLayout("))
        #expect(windowPlayback.contains(".padding(.bottom, DesignTokens.Spacing.md)") == false)
        #expect(windowPlayback.contains("VStack(spacing: DesignTokens.Spacing.md)") == false)
        #expect(
            mainViewSource.contains("#if os(macOS)\nprivate struct WindowPlaybackPageLayout") == false
        )
        #expect(geometrySource.contains("nonisolated static func resolve("))
        #expect(
            enchronMacOSMembership.contains("PlayerUI/Domain/WindowPlaybackPageGeometry.swift,")
        )
    }

    @Test("visionOS window keeps controls in SwiftUI instead of a RealityView attachment")
    func visionWindowControlsAreNotRealityViewAttachments() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let surfaceSource = try String(
            contentsOf: repositoryRoot
                .appending(path: "XrPlayer/PlayerUI/Views/PlaybackVideoSurface.swift"),
            encoding: .utf8
        )
        let mainViewSource = try String(
            contentsOf: repositoryRoot.appending(path: "XrPlayer/MainView.swift"),
            encoding: .utf8
        )

        let visionSurface = try sourceRegion(
            named: "private var visionSurface: some View",
            endingAt: "#else",
            in: surfaceSource
        )

        #expect(visionSurface.contains("attachments:") == false)
        #expect(surfaceSource.contains("VisionWindowPlaybackControlPlane") == false)
        #expect(mainViewSource.contains("PlayerUI-window-playback-deck"))
    }

    @Test("spatial stop waits for PlaybackCore before restoring the browser")
    func spatialStopUsesTheCleanupBarrier() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let mainViewSource = try String(
            contentsOf: repositoryRoot.appending(path: "XrPlayer/MainView.swift"),
            encoding: .utf8
        )
        let launchSource = try String(
            contentsOf: repositoryRoot
                .appending(path: "XrPlayer/App/PlaybackLaunchCoordinator.swift"),
            encoding: .utf8
        )
        let runtimeSource = try String(
            contentsOf: repositoryRoot.appending(path: "XrPlayer/App/PlaybackRuntime.swift"),
            encoding: .utf8
        )
        let immersiveSurfaceSource = try String(
            contentsOf: repositoryRoot
                .appending(path: "XrPlayer/SpatialScene/Scenes/ImmersiveSpaceView.swift"),
            encoding: .utf8
        )

        let spatialControls = try sourceRegion(
            named: "struct SpatialPlaybackControlsRoot: View",
            endingAt: "#endif",
            in: mainViewSource
        )

        #expect(spatialControls.contains("stopSpatialPlayback"))
        #expect(spatialControls.contains("await playbackLauncher.stopPlaybackAndWait()"))
        #expect(spatialControls.contains("await dismissImmersiveSpace()"))
        #expect(spatialControls.contains("resetPlaybackPresentationForStoppedPlayback"))
        #expect(spatialControls.contains(".accessibilityLabel(\"Stop Playback\")"))
        guard let mainWindowOpen = spatialControls.range(of: "openWindow(id: \"main\")"),
              let controlsDismiss = spatialControls.range(
                of: "dismissWindow(id: \"playerControls\")"
              ) else {
            throw StructureTestError.missingRegion("spatial window recovery")
        }
        #expect(mainWindowOpen.lowerBound < controlsDismiss.lowerBound)
        #expect(launchSource.contains("public func stopPlaybackAndWait() async"))
        #expect(runtimeSource.contains("public func stopAndWait("))
        #expect(immersiveSurfaceSource.contains("videoEntity.components.remove(VideoPlayerComponent.self)"))
        #expect(immersiveSurfaceSource.contains("presentationObservation.cancel()"))
        #expect(immersiveSurfaceSource.contains("releaseRendererConsumer("))
    }

    private func sourceRegion(
        named startMarker: String,
        endingAt endMarker: String,
        in source: String
    ) throws -> Substring {
        guard let start = source.range(of: startMarker),
              let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex) else {
            throw StructureTestError.missingRegion(startMarker)
        }
        return source[start.lowerBound..<end.lowerBound]
    }

    private enum StructureTestError: Error {
        case missingRegion(String)
    }
}
