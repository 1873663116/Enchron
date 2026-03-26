import Foundation

/// Testable value type describing the EDR metadata to apply to a CAMetalLayer.
/// Decoupled from CAEDRMetadata so unit tests can verify the selection logic
/// without requiring a real layer or QuartzCore availability check.
enum EDRMetadataDescriptor: Equatable {
    case hdr10(minLuminance: Float, maxLuminance: Float, opticalOutputScale: Float)
    case hlg
}

enum EDRMetadataSelection {
    /// Reference white luminance in nits per ITU-R BT.2408.
    private static let referenceWhiteNits: Double = 203.0

    /// Pure function: determines which EDR metadata descriptor to use based on
    /// content HDR type and signal peak. Returns nil for SDR content.
    static func descriptor(
        for hdrType: PlaybackCoreDomain.HDRType,
        signalPeak: Double?
    ) -> EDRMetadataDescriptor? {
        switch hdrType {
        case .sdr:
            return nil
        case .hlg:
            return .hlg
        // WORKAROUND: DoVI mapped to hdr10 — Apple has no public CAEDRMetadata.dolbyVision API.
        // Remove when/if Apple adds dedicated DoVI EDR metadata support.
        case .hdr10, .hdr10Plus, .dolbyVision:
            let peak = signalPeak ?? 1.0
            let maxLuminance = Float(peak * referenceWhiteNits)
            return .hdr10(
                minLuminance: 0.0,
                maxLuminance: maxLuminance,
                opticalOutputScale: 100.0
            )
        }
    }
}
