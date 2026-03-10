import Foundation

extension PlaybackCoreDomain {
    public enum HDRType: String, Sendable, CaseIterable, Codable {
        case sdr
        case hdr10
        case hdr10Plus
        case dolbyVision
        case hlg
    }

    /// Describes the actual HDR output pipeline state, independent of content detection.
    public enum HDROutputMode: String, Sendable {
        /// Content is rendered through a verified HDR pipeline (native Metal HDR surface).
        case passthroughHDR
        /// HDR content is tone-mapped to SDR for display.
        case toneMappedSDR
        /// Fallback: content is HDR but output is a best-effort SDR preview
        /// (e.g., 10-bit buffer without verified HDR surface).
        case previewSDR
        /// HDR output is not supported on this device/configuration.
        case unsupported
    }
}
