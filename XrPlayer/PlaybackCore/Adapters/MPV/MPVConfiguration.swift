import Foundation

public struct MPVConfiguration: Sendable {
    public var enableHardwareDecoding: Bool
    public var outputPixelFormat: String
    public var enableHDRMetadataPassthrough: Bool
    public var profile: String
    public var vo: String
    public var gpuContext: String
    public var cache: Bool
    public var demuxerMaxBytes: String
    public var initialAudioTrack: String?
    public var initialSubtitleTrack: String?

    public init(
        enableHardwareDecoding: Bool = true,
        outputPixelFormat: String = "nv12",
        enableHDRMetadataPassthrough: Bool = true,
        profile: String = "fast",
        vo: String = "libmpv",
        gpuContext: String = "auto",
        cache: Bool = true,
        demuxerMaxBytes: String = "128MiB",
        initialAudioTrack: String? = nil,
        initialSubtitleTrack: String? = nil
    ) {
        self.enableHardwareDecoding = enableHardwareDecoding
        self.outputPixelFormat = outputPixelFormat
        self.enableHDRMetadataPassthrough = enableHDRMetadataPassthrough
        self.profile = profile
        self.vo = vo
        self.gpuContext = gpuContext
        self.cache = cache
        self.demuxerMaxBytes = demuxerMaxBytes
        self.initialAudioTrack = initialAudioTrack
        self.initialSubtitleTrack = initialSubtitleTrack
    }

    public var defaultOptions: [(String, String)] {
        var options: [(String, String)] = [
            ("profile", profile),
            ("vo", vo),
            ("gpu-context", gpuContext),
            ("hwdec", enableHardwareDecoding ? VideoToolboxBridge.hwdecOptionValue : "no"),
            ("hwdec-codecs", VideoToolboxBridge.hwdecCodecs),
            ("vd-lavc-dr", "yes"),
            ("cache", cache ? "yes" : "no"),
            ("demuxer-max-bytes", demuxerMaxBytes),
            ("video-sync", "audio"),
            ("interpolation", "no"),
            ("video-latency-hacks", "yes"),
            ("keep-open", "yes"),
            ("hr-seek", "yes"),
            ("target-colorspace-hint", "yes"),
            ("tone-mapping", "auto"),
            ("alpha", "no"),
            ("msg-level", "all=v")
        ]

        if enableHDRMetadataPassthrough {
            options.append(("hdr-compute-peak", "no"))
            options.append(("target-trc", "auto"))
            options.append(("target-prim", "auto"))
        }

        if let initialAudioTrack {
            options.append(("aid", initialAudioTrack))
        }

        if let initialSubtitleTrack {
            options.append(("sid", initialSubtitleTrack))
        }

        return options
    }
}
