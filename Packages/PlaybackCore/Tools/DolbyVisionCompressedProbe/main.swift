@preconcurrency import AVFoundation
import AppKit
import Foundation
import PlaybackFFmpegBridge

@MainActor
private struct DolbyVisionCompressedProbe {
    static func run() async {
        let fixtures = CommandLine.arguments.dropFirst().compactMap(Fixture.init(argument:))
        var results = [[String: Any]]()
        var failed = false

        for fixture in fixtures {
            do {
                let renderContext = RenderContext()
                results.append(try await probe(fixture, renderContext: renderContext))
            } catch {
                failed = true
                results.append([
                    "profile": fixture.profile,
                    "file": fixture.url.path,
                    "result": "failed",
                    "error": error.localizedDescription
                ])
            }
        }

        let report: [String: Any] = ["fixtures": results]
        let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data ?? Data())
        FileHandle.standardOutput.write(Data("\n".utf8))
        Foundation.exit(failed ? 1 : 0)
    }

    private static func probe(
        _ fixture: Fixture,
        renderContext: RenderContext
    ) async throws -> [String: Any] {
        await dumpNativeReference(fixture.url)
        let reader = try FFmpegCompressedReader(url: fixture.url)
        let renderer = renderContext.renderer
        let synchronizer = renderContext.synchronizer
        let receiver = renderContext.receiver
        synchronizer.rate = 0
        await receiver.flush(removingDisplayedImage: true)

        let deadline = ContinuousClock.now + .seconds(20)
        var enqueuedSamples = 0
        var decodeFailures = [String]()
        var formatSummary: FormatSummary?
        while ContinuousClock.now < deadline {
            if let displayed = renderer.displayedPixelBuffer() {
                guard let summary = formatSummary else { throw ProbeError.missingFormatDescription }
                try fixture.validate(summary, isMVHEVC: reader.isMVHEVC)
                synchronizer.rate = 0
                let result = probeResult(
                    fixture: fixture,
                    summary: summary,
                    enqueuedSamples: enqueuedSamples,
                    decodeFailures: decodeFailures,
                    isMVHEVC: reader.isMVHEVC,
                    displayed: displayed
                )
                await receiver.flush(removingDisplayedImage: true)
                return result
            }
            guard let sample = try reader.nextSample() else {
                while ContinuousClock.now < deadline {
                    if let displayed = renderer.displayedPixelBuffer() {
                        guard let summary = formatSummary else {
                            throw ProbeError.missingFormatDescription
                        }
                        try fixture.validate(summary, isMVHEVC: reader.isMVHEVC)
                        synchronizer.rate = 0
                        let result = probeResult(
                            fixture: fixture,
                            summary: summary,
                            enqueuedSamples: enqueuedSamples,
                            decodeFailures: decodeFailures,
                            isMVHEVC: reader.isMVHEVC,
                            displayed: displayed
                        )
                        await receiver.flush(removingDisplayedImage: true)
                        return result
                    }
                    try await Task.sleep(for: .milliseconds(20))
                }
                if !decodeFailures.isEmpty {
                    throw ProbeError.decodeFailures(decodeFailures)
                }
                throw ProbeError.reachedEndBeforeDisplay
            }
            guard CMSampleBufferGetNumSamples(sample) > 0,
                  let sampleFormat = CMSampleBufferGetFormatDescription(sample) else {
                continue
            }
            if formatSummary == nil {
                formatSummary = compressedFormatSummary(sampleFormat)
                dumpSampleMetadata(sample, label: "bridge")
                dumpFormatDescription(sampleFormat)
                if let block = CMSampleBufferGetDataBuffer(sample) {
                    let length = CMBlockBufferGetDataLength(block)
                    var pointer: UnsafeMutablePointer<Int8>?
                    CMBlockBufferGetDataPointer(
                        block,
                        atOffset: 0,
                        lengthAtOffsetOut: nil,
                        totalLengthOut: nil,
                        dataPointerOut: &pointer
                    )
                    if let pointer {
                        let head = Data(bytes: pointer, count: min(24, length))
                        FileHandle.standardError.write(
                            Data(
                                "sample bytes=\(length) pts=\(CMSampleBufferGetPresentationTimeStamp(sample).seconds) head=\(head.map { String(format: "%02x", $0) }.joined())\n".utf8
                            )
                        )
                    }
                }
                synchronizer.setRate(
                    1,
                    time: CMSampleBufferGetPresentationTimeStamp(sample)
                )
            }
            let receiverSample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(
                unsafeBuffer: sample
            )
            let outcome = try await receiver.enqueue(receiverSample)
            switch outcome {
            case .enqueued:
                enqueuedSamples += 1
            case .enqueuedWithDecodeFailures(let errors):
                enqueuedSamples += 1
                let remaining = max(0, 8 - decodeFailures.count)
                decodeFailures.append(
                    contentsOf: errors.prefix(remaining).map(\.localizedDescription)
                )
            case .cancelledDueToFlush:
                throw ProbeError.rendererCancelled
            case .cancelledDueToFlushRequiredToResume(let error):
                throw error
            case .cancelledDueToError(let error):
                throw error
            @unknown default:
                throw ProbeError.rendererFailed
            }
        }
        if !decodeFailures.isEmpty {
            throw ProbeError.decodeFailures(decodeFailures)
        }
        throw ProbeError.timedOut
    }

    private static func dumpNativeReference(_ url: URL) async {
        do {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { return }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            let provider = reader.outputProvider(for: output)
            try reader.start()
            while let ready = try await provider.next() {
                let sample = try ready.withUnsafeSampleBuffer { try CMSampleBuffer(copying: $0) }
                guard let format = CMSampleBufferGetFormatDescription(sample) else { continue }
                dumpFormatDescription(format)
                dumpSampleMetadata(sample, label: "native")
                break
            }
            reader.cancelReading()
        } catch {
            FileHandle.standardError.write(Data("native reference error=\(error)\n".utf8))
        }
    }

    private static func dumpSampleMetadata(_ sample: CMSampleBuffer, label: String) {
        var timing = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timing)
        let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sample,
            createIfNecessary: false
        )
        FileHandle.standardError.write(
            Data("\(label) timing=\(timing) attachments=\(String(describing: attachments))\n".utf8)
        )
    }

    private static func probeResult(
        fixture: Fixture,
        summary: FormatSummary,
        enqueuedSamples: Int,
        decodeFailures: [String],
        isMVHEVC: Bool,
        displayed: CVPixelBuffer
    ) -> [String: Any] {
        [
            "profile": fixture.profile,
            "file": fixture.url.path,
            "result": "passed",
            "mediaSubtype": summary.mediaSubtype,
            "hvcC": summary.hvcC,
            "dvcC": summary.dvcC,
            "dvvC": summary.dvvC,
            "amve": summary.amve,
            "mvHEVC": isMVHEVC,
            "enqueuedSamples": enqueuedSamples,
            "decodeFailures": decodeFailures,
            "displayedPixelFormat": fourCC(CVPixelBufferGetPixelFormatType(displayed)),
            "rendererInput": "FFmpeg compressed CMSampleBuffer → AVSampleBufferVideoRenderer.Receiver"
        ]
    }

    private static func compressedFormatSummary(_ format: CMFormatDescription) -> FormatSummary {
        let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
        let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String]
            as? [String: Any] ?? [:]
        return FormatSummary(
            mediaSubtype: fourCC(CMFormatDescriptionGetMediaSubType(format)),
            hvcC: atoms["hvcC"] != nil,
            dvcC: atoms["dvcC"] != nil,
            dvvC: atoms["dvvC"] != nil,
            amve: extensions[kCMFormatDescriptionExtension_AmbientViewingEnvironment as String] != nil ||
                atoms["amve"] != nil
        )
    }

    private static func dumpFormatDescription(_ format: CMFormatDescription) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        var lines = [
            "formatDims \(dimensions.width)x\(dimensions.height)",
            "formatSubtype \(fourCC(CMFormatDescriptionGetMediaSubType(format)))"
        ]
        let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
        for key in extensions.keys.sorted() where key != "SampleDescriptionExtensionAtoms" {
            lines.append("ext \(key)=\(extensions[key] ?? "nil")")
        }
        if let atoms = extensions["SampleDescriptionExtensionAtoms"] as? [String: Any] {
            for key in atoms.keys.sorted() {
                if let data = atoms[key] as? Data {
                    let head = data.prefix(24).map { String(format: "%02x", $0) }.joined()
                    lines.append("atom \(key) len=\(data.count) head=\(head)")
                } else {
                    lines.append("atom \(key)=\(atoms[key] ?? "nil")")
                }
            }
        }
        FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    private static func fourCC(_ value: OSType) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? String(format: "0x%08X", value)
    }
}

private final class FFmpegCompressedReader {
    private let reader: OpaquePointer

    var isMVHEVC: Bool { PBFFmpegReaderIsMVHEVC(reader) }

    init(url: URL) throws {
        var error = [CChar](repeating: 0, count: 512)
        let opened = url.path.withCString { path in
            PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, 0, &error, error.count)
        }
        guard let opened else {
            throw ProbeError.ffmpeg(Self.message(error))
        }
        reader = opened
    }

    deinit {
        PBFFmpegReaderDestroy(reader)
    }

    func nextSample() throws -> CMSampleBuffer? {
        var error = [CChar](repeating: 0, count: 512)
        var sample: Unmanaged<CMSampleBuffer>?
        switch PBFFmpegReaderCopyNextSample(reader, &sample, &error, error.count) {
        case PBFFmpegReadResultSample:
            return sample?.takeRetainedValue()
        case PBFFmpegReadResultEnd:
            return nil
        case PBFFmpegReadResultCancelled:
            throw CancellationError()
        default:
            throw ProbeError.ffmpeg(Self.message(error))
        }
    }

    private static func message(_ buffer: [CChar]) -> String {
        String(
            decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }
}

@MainActor
private final class RenderContext {
    let window: NSWindow
    let renderer: AVSampleBufferVideoRenderer
    let synchronizer = AVSampleBufferRenderSynchronizer()
    let receiver: AVSampleBufferVideoRenderer.Receiver

    init() {
        _ = NSApplication.shared
        let displayLayer = AVSampleBufferDisplayLayer()
        let frame = NSRect(x: -1200, y: -800, width: 960, height: 540)
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        displayLayer.frame = view.bounds
        view.layer?.addSublayer(displayLayer)
        window.contentView = view
        window.orderFrontRegardless()

        self.window = window
        self.renderer = displayLayer.sampleBufferRenderer
        self.receiver = synchronizer.sampleBufferReceiver(adding: renderer)
    }
}

private struct Fixture {
    let profile: String
    let url: URL

    init?(argument: String) {
        guard let separator = argument.firstIndex(of: "=") else { return nil }
        let profile = String(argument[..<separator])
        guard [
            "5", "8.1", "8.4", "10.0", "10.1", "10.4", "20",
            "prores-422", "prores-4444-xq", "mv-hevc",
        ].contains(profile) else {
            return nil
        }
        self.profile = profile
        self.url = URL(fileURLWithPath: String(argument[argument.index(after: separator)...]))
    }

    func validate(_ summary: FormatSummary, isMVHEVC: Bool) throws {
        switch profile {
        case "5":
            guard summary.mediaSubtype == "dvh1", summary.dvcC else {
                throw ProbeError.invalidCompressedContract(profile)
            }
        case "8.1", "8.4":
            guard summary.mediaSubtype == "hvc1", summary.dvvC else {
                throw ProbeError.invalidCompressedContract(profile)
            }
        case "10.0", "10.1", "10.4":
            guard summary.mediaSubtype == "av01", summary.dvvC else {
                throw ProbeError.invalidCompressedContract(profile)
            }
        case "20":
            guard summary.mediaSubtype == "dvh1", summary.dvcC, isMVHEVC else {
                throw ProbeError.invalidCompressedContract(profile)
            }
        case "prores-422":
            guard summary.mediaSubtype == "apcn" else {
                throw ProbeError.invalidCompressedContract(profile)
            }
        case "prores-4444-xq":
            guard summary.mediaSubtype == "ap4x" else {
                throw ProbeError.invalidCompressedContract(profile)
            }
        case "mv-hevc":
            guard summary.mediaSubtype == "hvc1", isMVHEVC else {
                throw ProbeError.invalidCompressedContract(profile)
            }
        default:
            throw ProbeError.invalidCompressedContract(profile)
        }
    }
}

private struct FormatSummary {
    let mediaSubtype: String
    let hvcC: Bool
    let dvcC: Bool
    let dvvC: Bool
    let amve: Bool
}

private enum ProbeError: LocalizedError {
    case decodeFailures([String])
    case ffmpeg(String)
    case rendererCancelled
    case rendererRequiresFlush
    case rendererFailed
    case missingFormatDescription
    case reachedEndBeforeDisplay
    case timedOut
    case invalidCompressedContract(String)

    var errorDescription: String? {
        switch self {
        case .decodeFailures(let failures): failures.joined(separator: " | ")
        case .ffmpeg(let message): message
        case .rendererCancelled: "Renderer enqueue was cancelled by a flush."
        case .rendererRequiresFlush: "Renderer requires a flush before decoding can resume."
        case .rendererFailed: "AVSampleBufferVideoRenderer failed."
        case .missingFormatDescription: "The compressed sample has no format description."
        case .reachedEndBeforeDisplay: "The source ended before a displayed pixel buffer appeared."
        case .timedOut: "No displayed pixel buffer appeared within 20 seconds."
        case .invalidCompressedContract(let profile):
            "\(profile) did not preserve its compressed storage-format contract."
        }
    }
}

Task { @MainActor in
    await DolbyVisionCompressedProbe.run()
}
RunLoop.main.run()
