import Foundation

public struct MPVConfiguration: Sendable {
    public var useNativeGPUOutput: Bool
    public var enableHardwareDecoding: Bool
    public var outputPixelFormat: String
    public var enableHDRMetadataPassthrough: Bool
    public var hdrEnabled: Bool
    public var profile: String
    public var vo: String
    public var gpuAPI: String
    public var gpuContext: String
    public var cache: Bool
    public var demuxerMaxBytes: String
    public var initialAudioTrack: String?
    public var initialSubtitleTrack: String?
    public var hdrOutputPixelFormat: String
    public var forceLibmpvForHDR: Bool

    /// Directory containing bundled subtitle fonts.
    /// Automatically resolves to the app bundle's Fonts subfolder at runtime.
    /// Some Xcode filesystem-synchronised projects flatten loose font files into the
    /// app bundle root instead of preserving the Fonts/ directory, so we fall back
    /// to Bundle.main.resourcePath when the font is present there.
    public static var bundledFontsDir: String? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let fileManager = FileManager.default
        let fontsSubdirectory = "\(resourcePath)/Fonts"
        if fileManager.fileExists(atPath: fontsSubdirectory) {
            return fontsSubdirectory
        }
        if fileManager.fileExists(atPath: "\(resourcePath)/NotoSansSC-Regular.otf") {
            return resourcePath
        }
        return nil
    }

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
        hdrEnabled: Bool = true,
        profile: String = "fast",
        vo: String? = nil,
        gpuAPI: String? = nil,
        gpuContext: String? = nil,
        cache: Bool = true,
        demuxerMaxBytes: String = "16MiB",
        initialAudioTrack: String? = nil,
        initialSubtitleTrack: String? = nil,
        hdrOutputPixelFormat: String = "p010",
        forceLibmpvForHDR: Bool = false
    ) {
        self.useNativeGPUOutput = useNativeGPUOutput ?? MPVConfiguration.defaultUseNativeGPUOutput
        self.enableHardwareDecoding = enableHardwareDecoding
        self.outputPixelFormat = outputPixelFormat
        self.enableHDRMetadataPassthrough = enableHDRMetadataPassthrough
        self.hdrEnabled = hdrEnabled
        self.profile = profile
        self.vo = vo ?? MPVConfiguration.defaultVO(useNativeGPUOutput: self.useNativeGPUOutput)
        self.gpuAPI = gpuAPI ?? MPVConfiguration.defaultGPUAPI
        self.gpuContext = gpuContext ?? MPVConfiguration.defaultGPUContext
        self.cache = cache
        self.demuxerMaxBytes = demuxerMaxBytes
        self.initialAudioTrack = initialAudioTrack
        self.initialSubtitleTrack = initialSubtitleTrack
        self.hdrOutputPixelFormat = hdrOutputPixelFormat
        self.forceLibmpvForHDR = forceLibmpvForHDR
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
            ("hwdec", enableHardwareDecoding ? (useNativeGPUOutput ? "videotoolbox" : "videotoolbox-copy") : "no"),
            ("hwdec-codecs", VideoToolboxBridge.hwdecCodecs),
            ("vd-lavc-dr", "yes"),
            ("cache", cache ? "yes" : "no"),
            ("demuxer-max-bytes", demuxerMaxBytes),
            // Reduce readahead for faster first-frame on local files.
            // 0.5 s is enough to avoid stutters while minimising pre-buffer cost.
            ("demuxer-readahead-secs", "0.5"),
            ("video-sync", effectiveVideoSync),
            ("audio-buffer", "0.40"),
            ("interpolation", "no"),
            ("video-latency-hacks", "yes"),
            ("keep-open", "yes"),
            ("hr-seek", "yes"),
            ("target-colorspace-hint", hdrEnabled ? "auto" : "no"),
            ("tone-mapping", "auto"),
            ("msg-level", "all=warn"),
            ("sub-codepage", "utf-8"),
            ("sub-auto", "no"),              // never auto-select subtitle track
            ("sub-font", "Noto Sans SC"),    // bundled CJK font in XrPlayer/Fonts/
            ("sub-font-size", "55"),
            ("sub-ass-hinting", "none"),
            ("sub-fix-timing", "no"),
            ("sub-ass-force-margins", "no"),
            // Disable fontconfig-based font discovery: fontconfig does not exist
            // on visionOS. All fonts must come from sub-fonts-dir instead.
            ("sub-font-provider", "none"),
            // Blend subtitles into the video pipeline so libass output is
            // composited on the GPU rather than going through a separate OSD path.
            // This is safe now that the font is bundled (font lookup is fast).
            ("blend-subtitles", "yes")
        ]

        // Simulator uses software rendering; complex ASS effects (animations,
        // shadows, borders) saturate the CPU and cause choppy video.
        // Strip ASS override tags so subtitles render as plain text — fast and
        // correct.  On real device the M2 GPU handles full ASS without issue.
        #if targetEnvironment(simulator)
        options.append(("sub-ass-override", "strip"))
        #endif

        // In native GPU path (vo=gpu-next + hwdec=videotoolbox), VideoToolbox outputs
        // NV12-compatible CVPixelBuffers that gpu-next consumes zero-copy via MoltenVK.
        // Inserting an explicit format= filter breaks the zero-copy path and adds a CPU
        // conversion step. Only apply the filter for software-render paths (vo=libmpv).
        if outputPixelFormat.isEmpty == false && !effectiveVO.contains("gpu") {
            options.append(("vf", "format=\(outputPixelFormat)"))
        }

        if effectiveVO.contains("gpu") {
            options.append(("gpu-api", gpuAPI))
            options.append(("gpu-context", gpuContext))
        }

        if enableHDRMetadataPassthrough {
            options.append(("hdr-compute-peak", "no"))
            options.append(("target-trc", "auto"))
            options.append(("target-prim", "auto"))
        }

        if hdrEnabled == false {
            options.append(("target-trc", "srgb"))
            options.append(("target-prim", "bt.709"))
        }

        if let initialAudioTrack {
            options.append(("aid", initialAudioTrack))
        }

        if let initialSubtitleTrack {
            options.append(("sid", initialSubtitleTrack))
        } else {
            options.append(("sid", "no"))
        }

        // Point libass to the bundled fonts directory so it can find NotoSansSC.
        // This must be set even when sub-font-provider=none, because that option
        // only disables fontconfig scanning — sub-fonts-dir is still honoured.
        if let fontsDir = MPVConfiguration.bundledFontsDir {
            options.append(("sub-fonts-dir", fontsDir))
        }

        return options
    }

    public var defaultOptions: [(String, String)] {
        options(useNativeGPUOutput: useNativeGPUOutput)
    }

    /// Commands to enable HDR passthrough — let the display handle tone mapping.
    public func hdrRuntimeCommands() -> [[String]] {
        [
            ["set", "target-trc", "auto"],
            ["set", "target-prim", "auto"]
        ]
    }

    /// Commands to force SDR output — MPV performs tone mapping to sRGB/BT.709.
    public func sdrRuntimeCommands() -> [[String]] {
        [
            ["set", "target-trc", "srgb"],
            ["set", "target-prim", "bt.709"]
        ]
    }
}
