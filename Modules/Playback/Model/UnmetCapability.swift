import Foundation

public struct UnmetCapability: Sendable, Equatable, Identifiable {
    public let id: String
    public let requested: String
    public let delivered: String
    public let reason: String
    public let preventsPlayback: Bool

    public init(
        id: String,
        requested: String,
        delivered: String,
        reason: String,
        preventsPlayback: Bool
    ) {
        self.id = id
        self.requested = requested
        self.delivered = delivered
        self.reason = reason
        self.preventsPlayback = preventsPlayback
    }

    public var summary: String {
        preventsPlayback ? reason : "\(requested). \(delivered)."
    }
}

public struct PlaybackCapabilityFacts: Sendable, Equatable {
    public var codecName: String
    public var sourceIsMultiview: Bool
    public var deliveredIsMultiview: Bool
    public var audioRetired: Bool
    public var audioRetirementReason: String?
    public var rendererFailedToDecode: Bool

    public init(
        codecName: String = "unknown",
        sourceIsMultiview: Bool = false,
        deliveredIsMultiview: Bool = false,
        audioRetired: Bool = false,
        audioRetirementReason: String? = nil,
        rendererFailedToDecode: Bool = false
    ) {
        self.codecName = codecName
        self.sourceIsMultiview = sourceIsMultiview
        self.deliveredIsMultiview = deliveredIsMultiview
        self.audioRetired = audioRetired
        self.audioRetirementReason = audioRetirementReason
        self.rendererFailedToDecode = rendererFailedToDecode
    }
}

extension UnmetCapability {
    static let codecsWithoutDeviceDecoder = ["prores", "prores_raw"]

    public static func all(from facts: PlaybackCapabilityFacts) -> [UnmetCapability] {
        var found: [UnmetCapability] = []

        let codec = facts.codecName.lowercased()
        if codecsWithoutDeviceDecoder.contains(where: codec.contains),
           facts.rendererFailedToDecode {
            found.append(
                UnmetCapability(
                    id: "codec.noDeviceDecoder",
                    requested: "ProRes video",
                    delivered: "No picture",
                    reason: "This device has no ProRes decoder, so this file cannot play.",
                    preventsPlayback: true
                )
            )
        }

        if facts.sourceIsMultiview, facts.deliveredIsMultiview == false {
            found.append(
                UnmetCapability(
                    id: "video.multiviewFlattened",
                    requested: "Two views",
                    delivered: "Showing one view",
                    reason: "The second view could not be read from this file.",
                    preventsPlayback: false
                )
            )
        }

        if facts.audioRetired {
            found.append(
                UnmetCapability(
                    id: "audio.retired",
                    requested: "Sound",
                    delivered: "Playing silently",
                    reason: facts.audioRetirementReason
                        ?? "This device cannot decode the audio track in this file.",
                    preventsPlayback: false
                )
            )
        }

        return found
    }
}
