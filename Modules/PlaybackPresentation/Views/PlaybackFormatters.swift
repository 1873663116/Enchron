import Foundation
import PlaybackFeature
import PlaybackPresentation


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

    static func videoCodecLabel(_ codec: String?) -> String {
        guard let codec, !codec.isEmpty else { return "Unknown" }
        switch codec.lowercased() {
        case "hevc", "h265", "hvc1", "hev1": return "HEVC"
        case "h264", "avc", "avc1": return "H.264"
        case "av1", "av01": return "AV1"
        case "vp9": return "VP9"
        case "vp8": return "VP8"
        case "mpeg4video", "mp4v": return "MPEG-4"
        case "mpeg2video": return "MPEG-2"
        default: return codec.uppercased()
        }
    }

    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "Unknown" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    static func hdrTypeLabel(_ hdrType: PlaybackModel.HDRType) -> String {
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


enum PlaybackTimeFormatter {
    static func clock(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    static func preciseClock(_ seconds: Double, framesPerSecond: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if framesPerSecond > 0 {
            let frame = Int(seconds.truncatingRemainder(dividingBy: 1) * framesPerSecond)
            return String(format: "%02d:%02d:%02d.%02d", h, m, s, frame)
        }
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
