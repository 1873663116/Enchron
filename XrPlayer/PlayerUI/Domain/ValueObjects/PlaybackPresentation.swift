import Foundation

public enum PlaybackPresentation: String, Codable, CaseIterable, Sendable {
    case window
    case docked
    case panorama
}

public enum EnvironmentContext: Equatable, Sendable {
    case none
    case active(SpatialSceneDomain.CinemaEnvironment)

    public var environment: SpatialSceneDomain.CinemaEnvironment? {
        guard case .active(let environment) = self else { return nil }
        return environment
    }
}

public struct PlaybackPresentationTransition: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let previousPresentation: PlaybackPresentation
    public let targetPresentation: PlaybackPresentation
    public let previousEnvironment: EnvironmentContext
    public let targetEnvironment: EnvironmentContext

    public init(
        id: UUID = UUID(),
        previousPresentation: PlaybackPresentation,
        targetPresentation: PlaybackPresentation,
        previousEnvironment: EnvironmentContext,
        targetEnvironment: EnvironmentContext
    ) {
        self.id = id
        self.previousPresentation = previousPresentation
        self.targetPresentation = targetPresentation
        self.previousEnvironment = previousEnvironment
        self.targetEnvironment = targetEnvironment
    }
}

public enum PlaybackPresentationTransitionError: Error, Equatable, Sendable {
    case transitionInFlight
    case alreadyPresented
    case directSpatialTransitionNotSupported
    case dockedPresentationRequiresEnvironment
}

public struct PlaybackPresentationState: Equatable, Sendable {
    public private(set) var presented: PlaybackPresentation
    public private(set) var environment: EnvironmentContext
    public private(set) var transition: PlaybackPresentationTransition?

    public init(
        presented: PlaybackPresentation = .window,
        environment: EnvironmentContext = .none
    ) {
        self.presented = presented
        self.environment = environment
    }

    @discardableResult
    public mutating func begin(
        _ target: PlaybackPresentation,
        environment requestedEnvironment: SpatialSceneDomain.CinemaEnvironment? = nil,
        defaultEnvironment: SpatialSceneDomain.CinemaEnvironment = .darkTheatre,
        id: UUID = UUID()
    ) throws -> PlaybackPresentationTransition {
        guard transition == nil else {
            throw PlaybackPresentationTransitionError.transitionInFlight
        }
        guard target != presented else {
            throw PlaybackPresentationTransitionError.alreadyPresented
        }
        if presented != .window, target != .window {
            throw PlaybackPresentationTransitionError.directSpatialTransitionNotSupported
        }

        let targetEnvironment: EnvironmentContext
        if target == .docked {
            targetEnvironment = .active(
                requestedEnvironment ?? environment.environment ?? defaultEnvironment
            )
        } else {
            targetEnvironment = environment
        }

        let next = PlaybackPresentationTransition(
            id: id,
            previousPresentation: presented,
            targetPresentation: target,
            previousEnvironment: environment,
            targetEnvironment: targetEnvironment
        )
        transition = next
        return next
    }

    public mutating func commit(_ id: UUID) throws {
        guard let transition, transition.id == id else {
            throw PlaybackPresentationTransitionError.transitionInFlight
        }
        if transition.targetPresentation == .docked,
           transition.targetEnvironment.environment == nil {
            throw PlaybackPresentationTransitionError.dockedPresentationRequiresEnvironment
        }
        presented = transition.targetPresentation
        environment = transition.targetEnvironment
        self.transition = nil
    }

    public mutating func rollback(_ id: UUID) {
        guard let transition, transition.id == id else { return }
        presented = transition.previousPresentation
        environment = transition.previousEnvironment
        self.transition = nil
    }

    public mutating func setEnvironment(_ environment: EnvironmentContext) throws {
        guard transition == nil else {
            throw PlaybackPresentationTransitionError.transitionInFlight
        }
        if presented == .docked, environment.environment == nil {
            throw PlaybackPresentationTransitionError.dockedPresentationRequiresEnvironment
        }
        self.environment = environment
    }
}
