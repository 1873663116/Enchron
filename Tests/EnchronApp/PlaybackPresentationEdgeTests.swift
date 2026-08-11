import PlaybackPresentation
import Testing

@Suite("Playback presentation edges")
struct PlaybackPresentationEdgeTests {
    @Test("Presentations map to their content families")
    func presentationsMapToTheirContentFamilies() {
        #expect(PlaybackPresentation.window.contentFamily == .flat)
        #expect(PlaybackPresentation.docked.contentFamily == .flat)
        #expect(PlaybackPresentation.portal.contentFamily == .panoramic)
        #expect(PlaybackPresentation.panorama.contentFamily == .panoramic)
    }

    @Test("Every ordered presentation pair maps to its edge")
    func everyOrderedPresentationPairMapsToItsEdge() {
        let cases: [(
            presentations: (
                source: PlaybackPresentation,
                target: PlaybackPresentation
            ),
            expected: PresentationEdge
        )] = [
            ((.window, .window), .inPlace),
            ((.window, .docked), .enterImmersive),
            ((.window, .portal), .projectionSwap),
            ((.window, .panorama), .illegal),
            ((.docked, .window), .exitImmersive),
            ((.docked, .docked), .inPlace),
            ((.docked, .portal), .illegal),
            ((.docked, .panorama), .illegal),
            ((.portal, .window), .projectionSwap),
            ((.portal, .docked), .illegal),
            ((.portal, .portal), .inPlace),
            ((.portal, .panorama), .enterImmersive),
            ((.panorama, .window), .illegal),
            ((.panorama, .docked), .illegal),
            ((.panorama, .portal), .exitImmersive),
            ((.panorama, .panorama), .inPlace)
        ]

        for testCase in cases {
            let actual = PlaybackPresentation.edge(
                from: testCase.presentations.source,
                to: testCase.presentations.target
            )
            #expect(
                actual == testCase.expected,
                "\(testCase.presentations.source.rawValue) -> \(testCase.presentations.target.rawValue)"
            )
        }
    }
}
