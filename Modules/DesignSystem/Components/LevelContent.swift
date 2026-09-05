import SwiftUI

private struct LevelContent<ID: Hashable>: ViewModifier {
    let id: ID

    func body(content: Content) -> some View {
        ZStack {
            content
                .id(id)
                .transition(DesignTokens.TransitionToken.levelReplace)
        }
        .animation(DesignTokens.AnimationToken.levelTransition, value: id)
    }
}

public extension View {
    func levelContent<ID: Hashable>(id: ID) -> some View {
        modifier(LevelContent(id: id))
    }
}
