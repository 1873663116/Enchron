@preconcurrency import AVFoundation
import AppKit
import Foundation

@MainActor
private struct DolbyVisionCompressedProbe {
    static func run() async {
        let fixtures = CommandLine.arguments.dropFirst().compactMap(Fixture.init(argument:))
        let renderContext = RenderContext()
        var results = [[String: Any]]()
        var failed = false

        for fixture in fixtures {
            do {
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
        let asset = AVURLAsset(url: fixture.url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProbeError.noVideoTrack
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        let outputProvider = reader.outputProvider(for: output)
        try reader.start()

        defer { reader.cancelReading() }
        let renderer = renderContext.renderer
        let synchronizer = renderContext.synchronizer
        let receiver = renderContext.receiver
        synchronizer.rate = 0
        await receiver.flush(removingDisplayedImage: true)

        let deadline = ContinuousClock.now + .seconds(20)
        var enqueuedSamples = 0
        var formatSummary: FormatSummary?
        while ContinuousClock.now < deadline {
            if let displayed = renderer.displayedPixelBuffer(), enqueuedSamples >= 12 {
                guard let summary = formatSummary else { throw ProbeError.missingFormatDescription }
                try fixture.validate(summary)
                synchronizer.rate = 0
                let result: [String: Any] = [
                    "profile": fixture.profile,
                    "file": fixture.url.path,
                    "result": "passed",
                    "mediaSubtype": summary.mediaSubtype,
                    "hvcC": summary.hvcC,
                    "dvcC": summary.dvcC,
                    "dvvC": summary.dvvC,
                    "amve": summary.amve,
                    "enqueuedSamples": enqueuedSamples,
                    "displayedPixelFormat": fourCC(CVPixelBufferGetPixelFormatType(displayed)),
                    "rendererInput": "AVSampleBufferVideoRenderer.Receiver"
                ]
                await receiver.flush(removingDisplayedImage: true)
                return result
            }
            guard let readySample = try await outputProvider.next() else {
                throw ProbeError.reachedEndBeforeDisplay
            }
            let sample = try readySample.withUnsafeSampleBuffer {
                try CMSampleBuffer(copying: $0)
            }
            guard CMSampleBufferGetNumSamples(sample) > 0,
                  let sampleFormat = CMSampleBufferGetFormatDescription(sample) else {
                continue
            }
            if formatSummary == nil {
                formatSummary = compressedFormatSummary(sampleFormat)
                synchronizer.setRate(1, time: CMSampleBufferGetPresentationTimeStamp(sample))
            }
            let receiverSample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(
                unsafeBuffer: sample
            )
            switch try await receiver.enqueue(receiverSample) {
            case .enqueued, .enqueuedWithDecodeFailures:
                enqueuedSamples += 1
            case .cancelledDueToFlush:
                throw ProbeError.rendererCancelled
            case .cancelledDueToFlushRequiredToResume(let error):
                throw error ?? ProbeError.rendererRequiresFlush
            case .cancelledDueToError(let error):
                throw error
            @unknown default:
                throw ProbeError.rendererFailed
            }
        }
        throw ProbeError.timedOut
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

    private static func fourCC(_ value: OSType) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? String(format: "0x%08X", value)
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
        guard ["5", "8.1", "8.4"].contains(profile) else { return nil }
        self.profile = profile
        self.url = URL(fileURLWithPath: String(argument[argument.index(after: separator)...]))
    }

    func validate(_ summary: FormatSummary) throws {
        switch profile {
        case "5":
            guard summary.mediaSubtype == "dvh1", summary.dvcC else {
                throw ProbeError.invalidCompressedContract(profile)
            }
        case "8.1", "8.4":
            guard summary.mediaSubtype == "hvc1", summary.dvvC else {
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
    case noVideoTrack
    case rendererCancelled
    case rendererRequiresFlush
    case rendererFailed
    case missingFormatDescription
    case reachedEndBeforeDisplay
    case timedOut
    case invalidCompressedContract(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "No video track."
        case .rendererCancelled: "Renderer enqueue was cancelled by a flush."
        case .rendererRequiresFlush: "Renderer requires a flush before decoding can resume."
        case .rendererFailed: "AVSampleBufferVideoRenderer failed."
        case .missingFormatDescription: "The compressed sample has no format description."
        case .reachedEndBeforeDisplay: "The source ended before a displayed pixel buffer appeared."
        case .timedOut: "No displayed pixel buffer appeared within 20 seconds."
        case .invalidCompressedContract(let profile):
            "Dolby Vision Profile \(profile) did not preserve its storage-format sample contract."
        }
    }
}

Task { @MainActor in
    await DolbyVisionCompressedProbe.run()
}
RunLoop.main.run()
