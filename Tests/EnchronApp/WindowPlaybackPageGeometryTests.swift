import CoreGraphics
import DesignSystem
import PlaybackFeature
import PlaybackPresentation
import Testing
@testable import Enchron

@Suite("Window playback page geometry")
struct WindowPlaybackPageGeometryTests {
    @Test("window playback bounds use the source display aspect ratio")
    func playbackWindowSizePolicy() {
        let portrait = WindowPlaybackLayout(
            resolution: .init(width: 1_080, height: 1_920),
            stereoLayout: .mono
        )

        #expect(abs(portrait.aspectRatio - 0.5625) < 0.001)
        #expect(portrait.hasPlaybackAspectRatio(portrait.minimumSize))
        #expect(portrait.hasPlaybackAspectRatio(portrait.defaultSize))
        #expect(portrait.hasPlaybackAspectRatio(portrait.maximumSize))
        #expect(portrait.contains(portrait.minimumSize))
        #expect(portrait.contains(portrait.defaultSize))
        #expect(portrait.contains(portrait.maximumSize))
    }

    @Test("stereo packing resolves the displayed video dimensions")
    func stereoscopicDisplayAspectRatio() {
        let sideBySide = WindowPlaybackLayout(
            resolution: .init(width: 3_840, height: 1_080),
            stereoLayout: .sideBySide
        )
        let topBottom = WindowPlaybackLayout(
            resolution: .init(width: 1_920, height: 2_160),
            stereoLayout: .topBottom
        )

        #expect(abs(sideBySide.aspectRatio - 16.0 / 9.0) < 0.001)
        #expect(abs(topBottom.aspectRatio - 16.0 / 9.0) < 0.001)
    }

    @Test("window width bounds derive from the rendered ornament width")
    func ornamentDrivenWindowWidths() {
        let layout = WindowPlaybackLayout.fallback

        #expect(DesignTokens.ControlBar.outerWidth == 728)
        #expect(layout.minimumSize == CGSize(width: 912, height: 513))
        #expect(layout.defaultSize == CGSize(width: 1_280, height: 720))
        #expect(layout.maximumSize == CGSize(width: 1_808, height: 1_017))
    }

    @Test("available canvas sizes resolve to a bounded source aspect surface")
    func fittedPlaybackWindowSizes() {
        let layout = WindowPlaybackLayout(aspectRatio: 4.0 / 3.0)
        let narrow = layout.sizeThatFits(
            CGSize(width: 1_000, height: 1_000)
        )
        let wide = layout.sizeThatFits(
            CGSize(width: 4_000, height: 800)
        )
        let tooSmall = layout.sizeThatFits(
            CGSize(width: 100, height: 100)
        )
        let tooLarge = layout.sizeThatFits(
            CGSize(width: 4_000, height: 4_000)
        )

        #expect(narrow == CGSize(width: 1_000, height: 750))
        #expect(abs(wide.width - 1_066.6666666666667) < 0.001)
        #expect(abs(wide.height - 800) < 0.001)
        #expect(tooSmall == layout.minimumSize)
        #expect(tooLarge == layout.maximumSize)
        #expect(layout.hasPlaybackAspectRatio(narrow))
        #expect(layout.hasPlaybackAspectRatio(wide))
        #expect(layout.hasPlaybackAspectRatio(tooSmall))
        #expect(layout.hasPlaybackAspectRatio(tooLarge))
    }

    @Test("window presentation never hosts the independent controls window")
    func spatialControlsScenePolicy() {
        #expect(
            SpatialPlaybackControlsScenePolicy.shouldHostControls(
                for: .window
            ) == false
        )
        #expect(
            SpatialPlaybackControlsScenePolicy.shouldHostControls(
                for: .docked
            )
        )
        #expect(
            SpatialPlaybackControlsScenePolicy.shouldHostControls(
                for: .panorama
            )
        )
    }
}
