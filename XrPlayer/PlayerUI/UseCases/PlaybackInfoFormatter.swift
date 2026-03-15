import Foundation

enum PlaybackInfoFormatter {
    static func frameRate(_ frameRate: Double) -> String {
        guard frameRate > 0 else {
            return "Unknown"
        }
        return String(format: "%.2f fps", frameRate)
    }

    static func fileSize(_ sizeInBytes: Int64?) -> String {
        guard let sizeInBytes, sizeInBytes > 0 else {
            return "Unknown"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeInBytes)
    }

    static func hdrOutputDescription(_ outputMode: PlaybackCoreDomain.HDROutputMode) -> String {
        switch outputMode {
        case .passthroughHDR:
            return "HDR Passthrough"
        case .toneMappedSDR:
            return "Tone-Mapped SDR"
        case .previewSDR:
            return "SDR Preview"
        case .unsupported:
            return "Unavailable"
        }
    }

    static func hdrTypeLabel(_ hdrType: PlaybackCoreDomain.HDRType) -> String {
        switch hdrType {
        case .sdr:
            return "SDR"
        case .hdr10:
            return "HDR10"
        case .hdr10Plus:
            return "HDR10+"
        case .dolbyVision:
            return "Dolby Vision"
        case .hlg:
            return "HLG"
        }
    }
}
