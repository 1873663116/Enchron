import SwiftUI

private struct LevelReadinessKey: PreferenceKey {
    static let defaultValue = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value && nextValue()
    }
}

enum LevelReveal {
    static func delay(contentIsReady: Bool) -> Duration {
        .seconds(
            contentIsReady
                ? DesignTokens.AnimationToken.levelExitDuration
                : DesignTokens.AnimationToken.levelPlaceholderThreshold
        )
    }

    static func remaining(pendingFor elapsed: Duration, contentIsReady: Bool) -> Duration {
        max(.zero, delay(contentIsReady: contentIsReady) - elapsed)
    }
}

private struct PendingLevel<ID: Hashable & Sendable>: Sendable {
    let id: ID
    let since: ContinuousClock.Instant
}

private struct RevealRequest<ID: Hashable & Sendable>: Hashable, Sendable {
    let id: ID
    let contentIsReady: Bool
}

private struct LevelContent<ID: Hashable & Sendable>: ViewModifier {
    let id: ID

    @State private var revealedID: ID?
    @State private var pending: PendingLevel<ID>?
    @State private var contentIsReady = true
    @State private var hasRevealedALevel = false

    func body(content: Content) -> some View {
        ZStack {
            content
                .id(id)
                .transition(DesignTokens.TransitionToken.levelReplace)
                .opacity(revealedID == id ? 1 : 0)
        }
        .animation(DesignTokens.AnimationToken.levelTransition, value: id)
        .onPreferenceChange(LevelReadinessKey.self) { isReady in
            Task { @MainActor in contentIsReady = isReady }
        }
        .task(id: RevealRequest(id: id, contentIsReady: contentIsReady)) {
            await reveal()
        }
    }

    @MainActor
    private func reveal() async {
        guard revealedID != id else { return }

        guard hasRevealedALevel else {
            hasRevealedALevel = true
            pending = nil
            revealedID = id
            return
        }

        let now = ContinuousClock.now
        let since: ContinuousClock.Instant
        if let pending, pending.id == id {
            since = pending.since
        } else {
            since = now
            pending = PendingLevel(id: id, since: now)
        }

        let wait = LevelReveal.remaining(pendingFor: now - since, contentIsReady: contentIsReady)
        if wait > .zero {
            guard (try? await Task.sleep(for: wait)) != nil else { return }
        }
        pending = nil
        withAnimation(DesignTokens.AnimationToken.levelEnter) {
            revealedID = id
        }
    }
}

public extension View {
    func levelContent<ID: Hashable & Sendable>(id: ID) -> some View {
        modifier(LevelContent(id: id))
    }

    func levelReadiness(_ isReady: Bool) -> some View {
        preference(key: LevelReadinessKey.self, value: isReady)
    }
}
