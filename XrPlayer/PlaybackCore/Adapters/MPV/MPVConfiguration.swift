import Foundation

public struct MPVConfiguration: Sendable {
    public var useNativeGPUOutput: Bool
    public var enableHardwareDecoding: Bool
    public var outputPixelFormat: String
    public var enableHDRMetadataPassthrough: Bool
    public var profile: String
    public var vo: String
    public var gpuAPI: String
    public var gpuContext: String
    public var cache: Bool
    public var demuxerMaxBytes: String
    public var initialAudioTrack: String?
    public var initialSubtitleTrack: String?

    private static let defaultUseNativeGPUOutput: Bool = {
#if targetEnvironment(simulator)
        return false
#else
        return true
#endif
    }()

    private static func defaultVO(useNativeGPUOutput: Bool) -> String {
        useNativeGPUOutput ? "gpu-next" : "libmpv"
    }

    private static let defaultGPUAPI: String = {
#if targetEnvironment(simulator)
        return "auto"
#else
        return "vulkan"
#endif
    }()

    private static let defaultGPUContext: String = {
#if targetEnvironment(simulator)
        return "auto"
#else
        return "moltenvk"
#endif
    }()

    public init(
        useNativeGPUOutput: Bool? = nil,
        enableHardwareDecoding: Bool = true,
        outputPixelFormat: String = "nv12",
        enableHDRMetadataPassthrough: Bool = true,
        profile: String = "fast",
        vo: String? = nil,
        gpuAPI: String? = nil,
        gpuContext: String? = nil,
        cache: Bool = true,
        demuxerMaxBytes: String = "128MiB",
        initialAudioTrack: String? = nil,
        initialSubtitleTrack: String? = nil
    ) {
        self.useNativeGPUOutput = useNativeGPUOutput ?? MPVConfiguration.defaultUseNativeGPUOutput
        self.enableHardwareDecoding = enableHardwareDecoding
        self.outputPixelFormat = outputPixelFormat
        self.enableHDRMetadataPassthrough = enableHDRMetadataPassthrough
        self.profile = profile
        self.vo = vo ?? MPVConfiguration.defaultVO(useNativeGPUOutput: self.useNativeGPUOutput)
        self.gpuAPI = gpuAPI ?? MPVConfiguration.defaultGPUAPI
        self.gpuContext = gpuContext ?? MPVConfiguration.defaultGPUContext
        self.cache = cache
        self.demuxerMaxBytes = demuxerMaxBytes
        self.initialAudioTrack = initialAudioTrack
        self.initialSubtitleTrack = initialSubtitleTrack
    }

    public func options(useNativeGPUOutput: Bool) -> [(String, String)] {
        let effectiveVO: String
        if vo.contains("gpu"), useNativeGPUOutput == false {
            effectiveVO = "libmpv"
        } else {
            effectiveVO = vo
        }
        let effectiveVideoSync = effectiveVO.contains("gpu") ? "display-resample" : "audio"

        var options: [(String, String)] = [
            ("profile", profile),
            ("vo", effectiveVO),
            ("hwdec", enableHardwareDecoding ? "videotoolbox-copy" : "no"),
            ("hwdec-codecs", VideoToolboxBridge.hwdecCodecs),
            ("vd-lavc-dr", "yes"),
            ("cache", cache ? "yes" : "no"),
            ("demuxer-max-bytes", demuxerMaxBytes),
            ("video-sync", effectiveVideoSync),
            ("audio-buffer", "0.40"),
            ("interpolation", "no"),
            ("video-latency-hacks", "yes"),
            ("keep-open", "yes"),
            ("hr-seek", "yes"),
            ("target-colorspace-hint", "yes"),
            ("tone-mapping", "auto"),
            ("msg-level", "all=warn")
        ]

        if effectiveVO.contains("gpu") {
            options.append(("gpu-api", gpuAPI))
            options.append(("gpu-context", gpuContext))
        }

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
        } else {
            options.append(("sid", "no"))
        }

        return options
    }

    public var defaultOptions: [(String, String)] {
        options(useNativeGPUOutput: useNativeGPUOutput)
    }
}
