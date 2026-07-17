import Foundation
import Testing

@Suite("Window playback surface structure")
struct WindowPlaybackSurfaceStructureTests {
    @Test("macOS keeps the transport deck outside the RealityKit canvas")
    func deckIsOutsideRealityKitCanvas() throws {
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

        #expect(macOSSurface.contains("WindowPlaybackControlPlane()") == false)
        #expect(windowPlayback.contains(".overlay(alignment: .top)"))
        #expect(windowPlayback.contains("PlayerInfoBarView()"))
        #expect(windowPlayback.contains("WindowPlayerDeckView()"))
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
