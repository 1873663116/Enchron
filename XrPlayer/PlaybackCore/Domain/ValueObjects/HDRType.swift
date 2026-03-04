import Foundation

extension PlaybackCoreDomain {
    public enum HDRType: String, Sendable, CaseIterable {
        case sdr
        case hdr10
        case hdr10Plus
        case dolbyVision
        case hlg
    }
}
