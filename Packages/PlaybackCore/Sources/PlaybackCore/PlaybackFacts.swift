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

public enum RendererInputKind: String, Codable, Sendable {
    case compressed
    case pixelBuffer
}

public struct ObservedStringFact: Codable, Equatable, Sendable {
    public var availability: FactAvailability
    public var value: String?

    public init(_ availability: FactAvailability, value: String? = nil) {
        self.availability = availability
        self.value = value
    }
}

public struct ObservedBooleanFact: Codable, Equatable, Sendable {
    public var availability: FactAvailability
    public var value: Bool?

    public init(_ availability: FactAvailability, value: Bool? = nil) {
        self.availability = availability
        self.value = value
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

