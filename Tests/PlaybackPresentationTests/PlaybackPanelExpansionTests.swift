import Playback
import Testing

@Test("a request shows the new block at once so both contents can crossfade together")
@MainActor
func aRequestSwitchesTheBlockImmediately() {
    var expansion = PlaybackPanelExpansion()
    expansion.request(.timeline)

    #expect(expansion.layout == .timeline)
    #expect(expansion.isShowing(.timeline))
    #expect(expansion.isShowing(.collapsed) == false)
    #expect(expansion.isExpanded)
}

@Test("pressing the block already showing collapses the panel")
@MainActor
func theBlockButtonToggles() {
    var expansion = PlaybackPanelExpansion(.timeline)
    expansion.toggle(.timeline)

    #expect(expansion.layout == .collapsed)
    #expect(expansion.isExpanded == false)
}

@Test("toggling a different block replaces the one showing")
@MainActor
func togglingAnotherBlockReplacesTheCurrentOne() {
    var expansion = PlaybackPanelExpansion(.timeline)
    expansion.toggle(.mediaInformation)

    #expect(expansion.isShowing(.mediaInformation))
    #expect(expansion.isShowing(.timeline) == false)
}

@Test("requesting the block already showing changes nothing")
@MainActor
func aRedundantRequestIsIgnored() {
    var expansion = PlaybackPanelExpansion(.settings)
    expansion.request(.settings)

    #expect(expansion == PlaybackPanelExpansion(.settings))
}

@Test("the collapsed panel is the one that is not expanded")
@MainActor
func onlyCollapsedIsUnexpanded() {
    #expect(PlaybackPanelExpansion().isExpanded == false)
    #expect(PlaybackPanelExpansion(.timeline).isExpanded)
    #expect(PlaybackPanelExpansion(.settings).isExpanded)
    #expect(PlaybackPanelExpansion(.mediaInformation).isExpanded)
}
