import PlaybackPresentation
import Testing

@Test("a change reaches the requested block only after the contents have left")
func aChangeLeavesBeforeItResizes() {
    var expansion = PlaybackPanelExpansion()
    expansion.request(.timeline)

    #expect(expansion.phase == .contentLeaving)
    #expect(expansion.layout == .collapsed)
    #expect(expansion.contentIsVisible == false)

    expansion.advance(from: .contentLeaving)
    #expect(expansion.phase == .resizing)
    #expect(expansion.layout == .timeline)
    #expect(expansion.contentIsVisible == false)

    expansion.advance(from: .resizing)
    #expect(expansion.phase == .settled)
    #expect(expansion.layout == .timeline)
    #expect(expansion.contentIsVisible)
}

@Test("a button reads as selected from the moment it is pressed")
func theButtonDoesNotFlickerBackWhileTheContentsLeave() {
    var expansion = PlaybackPanelExpansion()
    expansion.request(.settings)

    #expect(expansion.isShowing(.settings))
    #expect(expansion.isShowing(.collapsed) == false)
    #expect(expansion.layout == .collapsed)
}

@Test("pressing the block already showing collapses the panel")
func theBlockButtonToggles() {
    var expansion = PlaybackPanelExpansion(.timeline)
    expansion.toggle(.timeline)

    #expect(expansion.isShowing(.collapsed))
    expansion.advance(from: .contentLeaving)
    #expect(expansion.layout == .collapsed)
    #expect(expansion.isExpanded == false)
}

@Test("media information uses the same leave resize enter sequence")
func mediaInformationUsesThePanelExpansionSequence() {
    var expansion = PlaybackPanelExpansion()
    expansion.toggle(.mediaInformation)

    #expect(expansion.phase == .contentLeaving)
    #expect(expansion.layout == .collapsed)
    #expect(expansion.isShowing(.mediaInformation))

    expansion.advance(from: .contentLeaving)
    #expect(expansion.phase == .resizing)
    #expect(expansion.layout == .mediaInformation)
    #expect(expansion.contentIsVisible == false)

    expansion.advance(from: .resizing)
    #expect(expansion.phase == .settled)
    #expect(expansion.contentIsVisible)

    expansion.toggle(.mediaInformation)
    #expect(expansion.phase == .contentLeaving)
    #expect(expansion.isShowing(.collapsed))
}

@Test("requesting the block already showing does nothing")
func aRedundantRequestIsIgnored() {
    var expansion = PlaybackPanelExpansion(.settings)
    expansion.request(.settings)

    #expect(expansion.phase == .settled)
    #expect(expansion.contentIsVisible)
}

@Test("changing your mind mid-change retargets it rather than queueing behind it")
func aSecondRequestRetargets() {
    var expansion = PlaybackPanelExpansion()
    expansion.request(.timeline)
    expansion.request(.settings)

    #expect(expansion.phase == .contentLeaving)
    expansion.advance(from: .contentLeaving)
    #expect(expansion.layout == .settings)
}

@Test("a request during the resize sends the shell to the new block instead")
func aRequestDuringTheResizeTurnsTheShellAround() {
    var expansion = PlaybackPanelExpansion()
    expansion.request(.timeline)
    expansion.advance(from: .contentLeaving)
    #expect(expansion.phase == .resizing)

    expansion.request(.settings)
    #expect(expansion.phase == .contentLeaving)

    expansion.advance(from: .contentLeaving)
    #expect(expansion.layout == .settings)
    expansion.advance(from: .resizing)
    #expect(expansion.contentIsVisible)
}

@Test("a completion that lands after a newer request cannot skip a step")
func aStaleCompletionIsIgnored() {
    var expansion = PlaybackPanelExpansion()
    expansion.request(.timeline)
    expansion.advance(from: .contentLeaving)

    expansion.advance(from: .contentLeaving)

    #expect(expansion.phase == .resizing)
    #expect(expansion.contentIsVisible == false)
}

@Test("the collapsed panel is the one that is not expanded")
func onlyCollapsedIsUnexpanded() {
    #expect(PlaybackPanelExpansion().isExpanded == false)
    #expect(PlaybackPanelExpansion(.timeline).isExpanded)
    #expect(PlaybackPanelExpansion(.settings).isExpanded)
    #expect(PlaybackPanelExpansion(.mediaInformation).isExpanded)
}
