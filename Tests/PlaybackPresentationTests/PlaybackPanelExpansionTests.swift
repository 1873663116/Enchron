import DesignSystem
import PlaybackPresentation
import Testing

@Test("expanded flag follows layout directly")
func onlyCollapsedIsUnexpanded() {
    #expect(PlaybackPanelExpansion().isExpanded == false)
    #expect(PlaybackPanelExpansion(.timeline).isExpanded)
    #expect(PlaybackPanelExpansion(.settings).isExpanded)
    #expect(PlaybackPanelExpansion(.mediaInformation).isExpanded)
}

@Test("selected state follows layout without flicker")
func theButtonDoesNotFlickerBackWhileTheContentsLeave() {
    var expansion = PlaybackPanelExpansion()
    expansion.request(.settings)
    #expect(expansion.isShowing(.settings))
    #expect(expansion.isShowing(.collapsed) == false)
    #expect(expansion.layout == .settings)
}

@Test("requesting the same layout is a no-op")
func aRedundantRequestIsIgnored() {
    var expansion = PlaybackPanelExpansion(.settings)
    expansion.request(.settings)
    #expect(expansion.layout == .settings)
    #expect(expansion.isShowing(.settings))
}

@Test("pressing the block already showing collapses the panel")
func theBlockButtonToggles() {
    var expansion = PlaybackPanelExpansion(.timeline)
    expansion.toggle(.timeline)
    #expect(expansion.isShowing(.collapsed))
    #expect(expansion.layout == .collapsed)
    #expect(expansion.isExpanded == false)
}

@Test("toggling mediaInformation collapses when already showing it")
func mediaInformationUsesThePanelExpansionSequence() {
    var expansion = PlaybackPanelExpansion()
    expansion.toggle(.mediaInformation)
    #expect(expansion.isShowing(.mediaInformation))
    #expect(expansion.layout == .mediaInformation)
    expansion.toggle(.mediaInformation)
    #expect(expansion.isShowing(.collapsed))
    #expect(expansion.layout == .collapsed)
}

@Test("a second request retargets immediately without queueing")
func aSecondRequestRetargets() {
    var expansion = PlaybackPanelExpansion()
    expansion.request(.timeline)
    expansion.request(.settings)
    #expect(expansion.layout == .settings)
    #expect(expansion.isShowing(.settings))
}

@Test("retargeting mid-flight lands on the last requested layout")
func aRequestDuringTheResizeTurnsTheShellAround() {
    var expansion = PlaybackPanelExpansion()
    expansion.request(.timeline)
    #expect(expansion.layout == .timeline)
    expansion.request(.settings)
    #expect(expansion.layout == .settings)
}

@Test("each aside resolves to a chrome size")
func eachAsideHasAChromeSize() {
    let surfaces: [DesignTokens.PlayerPanelChrome.Surface] = [.windowOrnament, .playerControlDock]
    for surface in surfaces {
        for aside in DesignTokens.PlayerPanelChrome.Aside.allCases {
            let size = DesignTokens.PlayerPanelChrome.contentSize(for: aside, surface: surface)
            #expect(size.width > 0, "width for \(aside) on \(surface) must be positive")
            #expect(size.height > 0, "height for \(aside) on \(surface) must be positive")
        }
    }
    let collapsed = DesignTokens.PlayerPanelChrome.contentSize(for: .collapsed, surface: .windowOrnament)
    let timeline = DesignTokens.PlayerPanelChrome.contentSize(for: .timeline, surface: .windowOrnament)
    #expect(timeline.height > collapsed.height)
}

@Test("alias PlaybackPanelLayout refers to the same value object")
func layoutAliasMatchesExpansion() {
    var layout = PlaybackPanelLayout(.timeline)
    #expect(layout.isShowing(.timeline))
    layout.toggle(.timeline)
    #expect(layout.isShowing(.collapsed))
}
