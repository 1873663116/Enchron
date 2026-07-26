import Foundation

public enum PlaybackLifecycle: String, Codable, Sendable {
    case idle
    case opening
    case ready
    case playing
    case paused
    case ended
    case failed
}
public enum NodeOutcome: String, Codable, Sendable {
    case succeeded
    case failed
    case terminatedByCleanup
}

public enum PlaybackNode: Int, Codable, CaseIterable, Sendable {
    case sourceAcquisition = 1
    case mediaSessionBinding
    case providerOpen
    case videoTrackModel
    case mediaEventStream
    case videoSampleStream
    case rendererInputCoordination
    case realityKitRendererBinding
    case rendererConsumerBinding
}

public enum FactAvailability: String, Codable, Sendable {
    case known
    case none
    case unknown
    case notExposed
    case unsupported
    case notAvailable
}

/// Names the reasons an observed fact has no value; known facts use init(known:) instead.
public enum FactUnavailability: String, Codable, Sendable {
    case none
    case unknown
    case notExposed
    case unsupported
    case notAvailable

    fileprivate var availability: FactAvailability {
        switch self {
        case .none: .none
        case .unknown: .unknown
        case .notExposed: .notExposed
        case .unsupported: .unsupported
        case .notAvailable: .notAvailable
        }
    }

    fileprivate init(_ availability: FactAvailability) {
        switch availability {
        case .known:
            preconditionFailure("Known facts require init(known:).")
        case .none: self = .none
        case .unknown: self = .unknown
        case .notExposed: self = .notExposed
        case .unsupported: self = .unsupported
        case .notAvailable: self = .notAvailable
        }
    }
}

public enum RendererInputKind: String, Codable, Sendable {
    case compressed
    case pixelBuffer
}

/// Records a string fact as either one known value or one explicit unavailability reason.
public struct ObservedStringFact: Codable, Equatable, Sendable {
    private enum Storage: Equatable, Sendable {
        case known(String)
        case unavailable(FactUnavailability)
    }

    private let storage: Storage

    /// Reports whether a string fact is known without allowing availability and value to diverge.
    public var availability: FactAvailability {
        switch storage {
        case .known: .known
        case .unavailable(let unavailability): unavailability.availability
        }
    }

    /// Returns the observed string only when availability is known.
    public var value: String? {
        guard case .known(let value) = storage else { return nil }
        return value
    }

    /// Creates an observed string whose value is known.
    public init(known value: String) {
        storage = .known(value)
    }

    /// Creates an unavailable observed string fact.
    public init(_ unavailability: FactUnavailability) {
        storage = .unavailable(unavailability)
    }

    private enum CodingKeys: String, CodingKey {
        case availability
        case value
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let availability = try values.decode(FactAvailability.self, forKey: .availability)
        let value = try values.decodeIfPresent(String.self, forKey: .value)
        if availability == .known {
            guard let value else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: values,
                    debugDescription: "A known observed string fact requires a value."
                )
            }
            storage = .known(value)
        } else {
            storage = .unavailable(FactUnavailability(availability))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(availability, forKey: .availability)
        if let value {
            try values.encode(value, forKey: .value)
        }
    }
}

/// Records a Boolean fact as either one known value or one explicit unavailability reason.
public struct ObservedBooleanFact: Codable, Equatable, Sendable {
    private enum Storage: Equatable, Sendable {
        case known(Bool)
        case unavailable(FactUnavailability)
    }

    private let storage: Storage

    /// Reports whether a Boolean fact is known without allowing availability and value to diverge.
    public var availability: FactAvailability {
        switch storage {
        case .known: .known
        case .unavailable(let unavailability): unavailability.availability
        }
    }

    /// Returns the observed Boolean only when availability is known.
    public var value: Bool? {
        guard case .known(let value) = storage else { return nil }
        return value
    }

    /// Creates an observed Boolean whose value is known.
    public init(known value: Bool) {
        storage = .known(value)
    }

    /// Creates an unavailable observed Boolean fact.
    public init(_ unavailability: FactUnavailability) {
        storage = .unavailable(unavailability)
    }

    private enum CodingKeys: String, CodingKey {
        case availability
        case value
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let availability = try values.decode(FactAvailability.self, forKey: .availability)
        let value = try values.decodeIfPresent(Bool.self, forKey: .value)
        if availability == .known {
            guard let value else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: values,
                    debugDescription: "A known observed Boolean fact requires a value."
                )
            }
            storage = .known(value)
        } else {
            storage = .unavailable(FactUnavailability(availability))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(availability, forKey: .availability)
        if let value {
            try values.encode(value, forKey: .value)
        }
    }
}

public struct VideoFormatSignalingSummary: Codable, Equatable, Sendable {
    public var provenance: String
    public var colorPrimaries: ObservedStringFact
    public var transferFunction: ObservedStringFact
    public var yCbCrMatrix: ObservedStringFact
    public var range: ObservedStringFact
    public var projectionKind: ObservedStringFact
    public var viewPackingKind: ObservedStringFact
    public var hasLeftStereoEyeView: ObservedBooleanFact
    public var hasRightStereoEyeView: ObservedBooleanFact
    public var masteringDisplayMetadata: ObservedBooleanFact
    public var contentLightLevelMetadata: ObservedBooleanFact
    public var hvcC: ObservedBooleanFact
    public var dvcC: ObservedBooleanFact
    public var dvvC: ObservedBooleanFact
    public var ambientViewingEnvironment: ObservedBooleanFact

    public init(
        provenance: String,
        colorPrimaries: ObservedStringFact = .init(.notExposed),
        transferFunction: ObservedStringFact = .init(.notExposed),
        yCbCrMatrix: ObservedStringFact = .init(.notExposed),
        range: ObservedStringFact = .init(.notExposed),
        projectionKind: ObservedStringFact = .init(.notExposed),
        viewPackingKind: ObservedStringFact = .init(.notExposed),
        hasLeftStereoEyeView: ObservedBooleanFact = .init(.notExposed),
        hasRightStereoEyeView: ObservedBooleanFact = .init(.notExposed),
        masteringDisplayMetadata: ObservedBooleanFact = .init(.notExposed),
        contentLightLevelMetadata: ObservedBooleanFact = .init(.notExposed),
        hvcC: ObservedBooleanFact = .init(.notExposed),
        dvcC: ObservedBooleanFact = .init(.notExposed),
        dvvC: ObservedBooleanFact = .init(.notExposed),
        ambientViewingEnvironment: ObservedBooleanFact = .init(.notExposed)
    ) {
        self.provenance = provenance
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.yCbCrMatrix = yCbCrMatrix
        self.range = range
        self.projectionKind = projectionKind
        self.viewPackingKind = viewPackingKind
        self.hasLeftStereoEyeView = hasLeftStereoEyeView
        self.hasRightStereoEyeView = hasRightStereoEyeView
        self.masteringDisplayMetadata = masteringDisplayMetadata
        self.contentLightLevelMetadata = contentLightLevelMetadata
        self.hvcC = hvcC
        self.dvcC = dvcC
        self.dvvC = dvvC
        self.ambientViewingEnvironment = ambientViewingEnvironment
    }

    private enum CodingKeys: String, CodingKey {
        case provenance
        case colorPrimaries
        case transferFunction
        case yCbCrMatrix
        case range
        case projectionKind
        case viewPackingKind
        case hasLeftStereoEyeView
        case hasRightStereoEyeView
        case masteringDisplayMetadata
        case contentLightLevelMetadata
        case hvcC
        case dvcC
        case dvvC
        case ambientViewingEnvironment
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provenance = try values.decode(String.self, forKey: .provenance)
        colorPrimaries = try values.decode(ObservedStringFact.self, forKey: .colorPrimaries)
        transferFunction = try values.decode(ObservedStringFact.self, forKey: .transferFunction)
        yCbCrMatrix = try values.decode(ObservedStringFact.self, forKey: .yCbCrMatrix)
        range = try values.decode(ObservedStringFact.self, forKey: .range)
        projectionKind = try values.decodeIfPresent(
            ObservedStringFact.self,
            forKey: .projectionKind
        ) ?? .init(.notExposed)
        viewPackingKind = try values.decodeIfPresent(
            ObservedStringFact.self,
            forKey: .viewPackingKind
        ) ?? .init(.notExposed)
        hasLeftStereoEyeView = try values.decodeIfPresent(
            ObservedBooleanFact.self,
            forKey: .hasLeftStereoEyeView
        ) ?? .init(.notExposed)
        hasRightStereoEyeView = try values.decodeIfPresent(
            ObservedBooleanFact.self,
            forKey: .hasRightStereoEyeView
        ) ?? .init(.notExposed)
        masteringDisplayMetadata = try values.decode(
            ObservedBooleanFact.self,
            forKey: .masteringDisplayMetadata
        )
        contentLightLevelMetadata = try values.decode(
            ObservedBooleanFact.self,
            forKey: .contentLightLevelMetadata
        )
        hvcC = try values.decode(ObservedBooleanFact.self, forKey: .hvcC)
        dvcC = try values.decode(ObservedBooleanFact.self, forKey: .dvcC)
        dvvC = try values.decode(ObservedBooleanFact.self, forKey: .dvvC)
        ambientViewingEnvironment = try values.decode(
            ObservedBooleanFact.self,
            forKey: .ambientViewingEnvironment
        )
    }
}
