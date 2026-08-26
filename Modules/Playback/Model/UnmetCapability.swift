import Foundation

/// Something the media asked for that this build or this device did not deliver.
///
/// `PlaybackError` cannot carry these. Its cases are all terminal, so a title that
/// played with its second view missing, or played silently because the audio codec
/// was refused, had nowhere to be recorded and reached the wearer as an unexplained
/// picture. The distinction that decides where one of these is shown is whether
/// playback happened at all, so that is the only axis here. Anything finer, a
/// severity ladder for instance, would be a classification the surfaces cannot use.
public struct UnmetCapability: Sendable, Equatable, Identifiable {
    public let id: String
    /// What the media asked for, in the wearer's terms.
    public let requested: String
    /// What playback produced instead.
    public let delivered: String
    /// Why the substitution happened.
    public let reason: String
    /// True when there is no picture, which is the only case that interrupts.
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

    /// One sentence for a surface with no room for three fields.
    public var summary: String {
        preventsPlayback ? reason : "\(requested). \(delivered)."
    }
}

/// The facts a judgement needs, named so the judgement can be tested without a session.
///
/// Every field here is already published by PlaybackCore. Nothing in this file probes
/// the device; a capability that is not visible in these facts is a gap in the facts,
/// not something to infer from a heuristic.
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
    /// This device reports no decoder for any ProRes variant, measured through
    /// VTDecompressionSessionCreate rather than inferred from the renderer's error.
    /// See `Tests/EnchronApp/VideoDecoderAvailabilityTests.swift`.
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
