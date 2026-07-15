@preconcurrency import AVFoundation
import AppKit
import CryptoKit
import Foundation
import IOSurface
import VideoToolbox

private let fixtureURL = URL(fileURLWithPath: "/Users/xiongzhipeng/Desktop/test/HDR10/HDR10.MP4")
private let targetTime = CMTime(value: 450 * 1001, timescale: 60_000)

@MainActor
private struct HDRBoundaryProbe {
    static func run() async {
        do {
            let result = try await probe()
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            if result["verdict"] as? String != "UPSTREAM_INVARIANTS_HOLD" {
                Foundation.exit(1)
            }
            Foundation.exit(0)
        } catch {
            let result = ["verdict": "PROBE_ERROR", "error": error.localizedDescription]
            let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardError.write(data ?? Data())
            FileHandle.standardError.write(Data("\n".utf8))
            Foundation.exit(2)
        }
    }

    private static func probe() async throws -> [String: Any] {
        let asset = AVURLAsset(url: fixtureURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProbeError.noVideoTrack
        }
        let duration = try await asset.load(.duration)
        let trackDescriptions = try await track.load(.formatDescriptions)
        let trackFormats = trackDescriptions.map(formatSummary)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: targetTime, end: duration)
        let settings: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        let outputProvider = reader.outputProvider(for: output)
        try reader.start()
        guard let readySample = try await outputProvider.next() else {
            throw ProbeError.cannotReadFrame
        }
        let sourceSample = try readySample.withUnsafeSampleBuffer {
            try CMSampleBuffer(copying: $0)
        }
        guard let source = CMSampleBufferGetImageBuffer(sourceSample) else {
            throw ProbeError.cannotReadFrame
        }

        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.bounds = CGRect(x: 0, y: 0, width: 960, height: 540)
        let displayWindow = attachToDiagnosticWindow(displayLayer)
        defer { displayWindow.close() }
        let renderer = displayLayer.sampleBufferRenderer
        let destination = try transfer(source: source, renderer: renderer)
        let renderSample = try rebuild(sourceSample: sourceSample, destination: destination)

        let sourceSummary = try bufferSummary(source)
        let destinationSummary = try bufferSummary(destination)
        let rebuiltSummary = try sampleSummary(renderSample, destination: destination)
        let renderedSummary = try await rendererSummary(renderer: renderer, sample: renderSample)

        var failures: [String] = []
        if sourceSummary["planeSHA256"] as? [String] != destinationSummary["planeSHA256"] as? [String] {
            failures.append("pixelTransfer.pixelValues")
        }
        if sourceSummary["color"] as? [String: String] != destinationSummary["color"] as? [String: String] {
            failures.append("pixelTransfer.colorAttachments")
        }
        if sourceSummary["iosurfaceContentHeadroom"] as? String != destinationSummary["iosurfaceContentHeadroom"] as? String {
            failures.append("pixelTransfer.iosurfaceContentHeadroom")
        }
        if rebuiltSummary["imageBufferIsDestination"] as? Bool != true {
            failures.append("sampleRebuild.imageBufferIdentity")
        }
        if rebuiltSummary["color"] as? [String: String] != destinationSummary["color"] as? [String: String] {
            failures.append("sampleRebuild.colorDescription")
        }
        if let displayed = renderedSummary["displayedPixelBuffer"] as? [String: Any] {
            if displayed["planeSHA256"] as? [String] != destinationSummary["planeSHA256"] as? [String] {
                failures.append("renderer.pixelValues")
            }
            if displayed["color"] as? [String: String] != destinationSummary["color"] as? [String: String] {
                failures.append("renderer.colorAttachments")
            }
            if displayed["iosurfaceContentHeadroom"] as? String != destinationSummary["iosurfaceContentHeadroom"] as? String {
                failures.append("renderer.iosurfaceContentHeadroom")
            }
        }

        return [
            "verdict": failures.isEmpty ? "UPSTREAM_INVARIANTS_HOLD" : "BOUNDARY_DIVERGENCE",
            "failures": failures,
            "fixture": [
                "path": fixtureURL.path,
                "targetSeconds": finiteSeconds(targetTime),
                "actualPTSSeconds": finiteSeconds(CMSampleBufferGetPresentationTimeStamp(sourceSample))
            ],
            "trackFormats": trackFormats,
            "sourcePixelBuffer": sourceSummary,
            "pixelTransferDestination": destinationSummary,
            "rebuiltSample": rebuiltSummary,
            "renderer": renderedSummary
        ]
    }

    private static func transfer(
        source: CVPixelBuffer,
        renderer: AVSampleBufferVideoRenderer
    ) throws -> CVPixelBuffer {
        var attributes = renderer.recommendedPixelBufferAttributes.rawAttributes
        attributes[kCVPixelBufferPixelFormatTypeKey as String] = CVPixelBufferGetPixelFormatType(source)
        attributes[kCVPixelBufferWidthKey as String] = CVPixelBufferGetWidth(source)
        attributes[kCVPixelBufferHeightKey as String] = CVPixelBufferGetHeight(source)
        attributes[kCVPixelBufferIOSurfacePropertiesKey as String] = [String: String]()

        var pool: CVPixelBufferPool?
        let poolStatus = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
        guard poolStatus == kCVReturnSuccess, let pool else {
            throw ProbeError.cannotCreatePool(poolStatus)
        }
        var destination: CVPixelBuffer?
        let allocationStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destination)
        guard allocationStatus == kCVReturnSuccess, let destination else {
            throw ProbeError.cannotAllocateBuffer(allocationStatus)
        }

        var session: VTPixelTransferSession?
        let sessionStatus = VTPixelTransferSessionCreate(
            allocator: kCFAllocatorDefault,
            pixelTransferSessionOut: &session
        )
        guard sessionStatus == noErr, let session else {
            throw ProbeError.cannotCreateTransferSession(sessionStatus)
        }
        defer { VTPixelTransferSessionInvalidate(session) }
        let transferStatus = VTPixelTransferSessionTransferImage(session, from: source, to: destination)
        guard transferStatus == noErr else { throw ProbeError.cannotTransfer(transferStatus) }
        return destination
    }

    private static func attachToDiagnosticWindow(_ displayLayer: AVSampleBufferDisplayLayer) -> NSWindow {
        _ = NSApplication.shared
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
        return window
    }

    private static func rebuild(
        sourceSample: CMSampleBuffer,
        destination: CVPixelBuffer
    ) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sourceSample),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sourceSample),
            decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(sourceSample)
        )
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: destination,
            formatDescription: try CMVideoFormatDescription(imageBuffer: destination),
            sampleTiming: &timing,
            sampleBufferOut: &sample
        )
        guard status == noErr, let sample else { throw ProbeError.cannotRebuildSample(status) }
        return sample
    }

    private static func rendererSummary(
        renderer: AVSampleBufferVideoRenderer,
        sample: CMSampleBuffer
    ) async throws -> [String: Any] {
        let synchronizer = AVSampleBufferRenderSynchronizer()
        let receiver = synchronizer.sampleBufferReceiver(adding: renderer)
        synchronizer.setRate(0, time: CMSampleBufferGetPresentationTimeStamp(sample))
        let readySample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(
            unsafeBuffer: sample
        )
        let enqueueResult = try await receiver.enqueue(readySample)
        let enqueueSummary: String
        switch enqueueResult {
        case .enqueued:
            enqueueSummary = "enqueued"
        case .enqueuedWithDecodeFailures(let errors):
            enqueueSummary = errors.map(\.localizedDescription).joined(separator: " | ")
        case .cancelledDueToFlush:
            throw ProbeError.rendererCancelled
        case .cancelledDueToFlushRequiredToResume(let error):
            throw error ?? ProbeError.rendererRequiresFlush
        case .cancelledDueToError(let error):
            throw error
        @unknown default:
            throw ProbeError.rendererFailed
        }

        let deadline = Date().addingTimeInterval(2)
        var displayed: CVPixelBuffer?
        while Date() < deadline, displayed == nil {
            displayed = renderer.displayedPixelBuffer()
            try await Task.sleep(for: .milliseconds(10))
        }
        synchronizer.rate = 0

        var result: [String: Any] = [
            "enqueueResult": enqueueSummary
        ]
        if let displayed {
            result["displayedPixelBuffer"] = try bufferSummary(displayed)
        } else {
            result["displayedPixelBuffer"] = "notExposed"
        }
        return result
    }

    private static func sampleSummary(
        _ sample: CMSampleBuffer,
        destination: CVPixelBuffer
    ) throws -> [String: Any] {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sample),
              let format = CMSampleBufferGetFormatDescription(sample) else {
            throw ProbeError.invalidRebuiltSample
        }
        let formatColors = colorSummary(
            CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
        )
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
            .map { String(describing: $0) } ?? "none"
        return [
            "imageBufferIsDestination": imageBuffer === destination,
            "pixelFormat": fourCC(CVPixelBufferGetPixelFormatType(imageBuffer)),
            "color": formatColors,
            "formatExtensions": formatSummary(format),
            "sampleAttachments": attachments,
            "ptsSeconds": finiteSeconds(CMSampleBufferGetPresentationTimeStamp(sample)),
            "durationSeconds": finiteSeconds(CMSampleBufferGetDuration(sample))
        ]
    }

    private static func bufferSummary(_ buffer: CVPixelBuffer) throws -> [String: Any] {
        let attachments = CVBufferCopyAttachments(buffer, .shouldPropagate) as? [String: Any] ?? [:]
        let planeData = try copyPlaneData(buffer)
        return [
            "pixelFormat": fourCC(CVPixelBufferGetPixelFormatType(buffer)),
            "width": CVPixelBufferGetWidth(buffer),
            "height": CVPixelBufferGetHeight(buffer),
            "iosurfaceBacked": CVPixelBufferGetIOSurface(buffer) != nil,
            "iosurfaceContentHeadroom": contentHeadroom(buffer),
            "color": colorSummary(attachments),
            "hdrMetadata": hdrSummary(attachments),
            "luma": try lumaSummary(buffer),
            "planeSHA256": planeData.map(sha256)
        ]
    }

    private static func colorSummary(_ values: [String: Any]) -> [String: String] {
        let keys: [(String, CFString)] = [
            ("primaries", kCVImageBufferColorPrimariesKey),
            ("transfer", kCVImageBufferTransferFunctionKey),
            ("matrix", kCVImageBufferYCbCrMatrixKey),
            ("chromaTop", kCVImageBufferChromaLocationTopFieldKey),
            ("chromaBottom", kCVImageBufferChromaLocationBottomFieldKey)
        ]
        return Dictionary(uniqueKeysWithValues: keys.map { name, key in
            (name, values[key as String].map { String(describing: $0) } ?? "missing")
        })
    }

    private static func hdrSummary(_ values: [String: Any]) -> [String: String] {
        [
            "masteringDisplay": valueDescription(values[kCVImageBufferMasteringDisplayColorVolumeKey as String]),
            "contentLightLevel": valueDescription(values[kCVImageBufferContentLightLevelInfoKey as String])
        ]
    }

    private static func formatSummary(_ format: CMFormatDescription) -> [String: Any] {
        let values = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
        return [
            "mediaSubType": fourCC(CMFormatDescriptionGetMediaSubType(format)),
            "color": colorSummary(values),
            "hdrMetadata": [
                "masteringDisplay": valueDescription(values[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String]),
                "contentLightLevel": valueDescription(values[kCMFormatDescriptionExtension_ContentLightLevelInfo as String])
            ]
        ]
    }

    private static func contentHeadroom(_ buffer: CVPixelBuffer) -> String {
        guard let unmanagedSurface = CVPixelBufferGetIOSurface(buffer) else { return "noIOSurface" }
        let surface = unmanagedSurface.takeUnretainedValue()
        guard let unmanagedValue = IOSurfaceCopyValue(surface, kIOSurfaceContentHeadroom) else {
            return "missing"
        }
        return String(describing: unmanagedValue)
    }

    private static func copyPlaneData(_ buffer: CVPixelBuffer) throws -> [Data] {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange else {
            throw ProbeError.unsupportedPixelFormat(CVPixelBufferGetPixelFormatType(buffer))
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        return try (0..<CVPixelBufferGetPlaneCount(buffer)).map { plane in
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else {
                throw ProbeError.missingPlane(plane)
            }
            let height = CVPixelBufferGetHeightOfPlane(buffer, plane)
            let width = CVPixelBufferGetWidthOfPlane(buffer, plane)
            let sourceRowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
            let logicalRowBytes = width * (plane == 0 ? 2 : 4)
            var data = Data(capacity: logicalRowBytes * height)
            for row in 0..<height {
                data.append(base.advanced(by: row * sourceRowBytes).assumingMemoryBound(to: UInt8.self), count: logicalRowBytes)
            }
            return data
        }
    }

    private static func lumaSummary(_ buffer: CVPixelBuffer) throws -> [String: Any] {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange else {
            throw ProbeError.unsupportedPixelFormat(CVPixelBufferGetPixelFormatType(buffer))
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else {
            throw ProbeError.missingPlane(0)
        }

        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        var histogram = Array(repeating: 0, count: 1024)
        var sum: UInt64 = 0
        for row in 0..<height {
            let samples = base.advanced(by: row * rowBytes).assumingMemoryBound(to: UInt16.self)
            for column in 0..<width {
                let value = Int(UInt16(littleEndian: samples[column]) >> 6)
                histogram[value] += 1
                sum += UInt64(value)
            }
        }
        let count = width * height
        return [
            "meanCodeValue": Double(sum) / Double(count),
            "p50": percentile(histogram, count: count, fraction: 0.50),
            "p90": percentile(histogram, count: count, fraction: 0.90),
            "p99": percentile(histogram, count: count, fraction: 0.99),
            "aboveNominalVideoRangeFraction": Double(histogram[941...].reduce(0, +)) / Double(count)
        ]
    }

    private static func percentile(_ histogram: [Int], count: Int, fraction: Double) -> Int {
        let target = Int((Double(count - 1) * fraction).rounded(.down))
        var accumulated = 0
        for (value, frequency) in histogram.enumerated() {
            accumulated += frequency
            if accumulated > target { return value }
        }
        return histogram.count - 1
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func valueDescription(_ value: Any?) -> String {
        guard let value else { return "missing" }
        if let data = value as? Data {
            return data.map { String(format: "%02x", $0) }.joined()
        }
        return String(describing: value)
    }

    private static func fourCC(_ value: OSType) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? String(format: "0x%08X", value)
    }

    private static func finiteSeconds(_ time: CMTime) -> Any {
        let seconds = time.seconds
        return seconds.isFinite ? seconds : "invalid"
    }
}

Task { @MainActor in
    await HDRBoundaryProbe.run()
}
RunLoop.main.run()

private enum ProbeError: LocalizedError {
    case noVideoTrack
    case cannotReadFrame
    case rendererCancelled
    case rendererRequiresFlush
    case rendererFailed
    case cannotCreatePool(CVReturn)
    case cannotAllocateBuffer(CVReturn)
    case cannotCreateTransferSession(OSStatus)
    case cannotTransfer(OSStatus)
    case cannotRebuildSample(OSStatus)
    case invalidRebuiltSample
    case unsupportedPixelFormat(OSType)
    case missingPlane(Int)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "No video track."
        case .cannotReadFrame: "Could not read the target frame."
        case .rendererCancelled: "Renderer enqueue was cancelled by a flush."
        case .rendererRequiresFlush: "Renderer requires a flush before decoding can resume."
        case .rendererFailed: "Renderer returned an unknown failure."
        case .cannotCreatePool(let status): "Could not create pixel buffer pool: \(status)."
        case .cannotAllocateBuffer(let status): "Could not allocate destination pixel buffer: \(status)."
        case .cannotCreateTransferSession(let status): "Could not create pixel transfer session: \(status)."
        case .cannotTransfer(let status): "Pixel transfer failed: \(status)."
        case .cannotRebuildSample(let status): "Sample rebuild failed: \(status)."
        case .invalidRebuiltSample: "Rebuilt sample is missing its image buffer or format."
        case .unsupportedPixelFormat(let format): "Unsupported pixel format: \(format)."
        case .missingPlane(let plane): "Pixel buffer plane \(plane) has no base address."
        }
    }
}
