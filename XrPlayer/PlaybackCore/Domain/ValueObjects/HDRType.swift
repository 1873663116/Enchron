import Foundation

extension PlaybackCoreDomain {
    public enum HDRType: String, Sendable, CaseIterable, Codable {
        case sdr
        case hdr10
        case hdr10Plus
        case dolbyVision
        case hlg
    }

    /// Describes the renderer's selected HDR/SDR output path, independent of content detection.
    /// This is a capability/configuration label, not final-display HDR verification.
    public enum HDROutputMode: String, Sendable {
        /// Content is routed through an HDR/EDR-capable renderer path.
        case edrOutputPath
        /// HDR content is tone-mapped to SDR for display.
        case toneMappedSDR
        /// Fallback: content is HDR but output is a best-effort SDR preview
        /// (e.g., 10-bit buffer without verified HDR surface).
        case previewSDR
        /// HDR output is not supported on this device/configuration.
        case unsupported
    }
}
