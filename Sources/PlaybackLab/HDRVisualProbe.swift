import AppKit
import AVKit
import CoreGraphics
import CryptoKit
import ImageIO
import IOSurface
import RealityKit
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

struct HDRVisualProbeView: View {
    @State private var probe = HDRVisualProbeModel()

    var body: some View {
        ZStack {
            RealityView { content in
                content.add(probe.playback.videoEntity)
            }
            .opacity(probe.showsRealityKit ? 1 : 0)

            HDRSystemPlayerView(player: probe.playback.systemReferencePlayer)
                .opacity(probe.showsSystemReference ? 1 : 0)

            if case .failed(let message) = probe.stage {
                Text(message)
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 960, height: 540)
        .background(.black)
        .task {
            await probe.run()
        }
    }
}

private struct HDRSystemPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}

@MainActor
@Observable
private final class HDRVisualProbeModel {
    enum Stage {
        case realityKit
        case realityKitAVPlayer
        case systemReference
        case failed(String)
    }

    let playback = PlaybackModel()
    var stage = Stage.realityKit

    var showsRealityKit: Bool {
        switch stage {
        case .realityKit, .realityKitAVPlayer: true
        default: false
        }
    }

    var showsSystemReference: Bool {
        if case .systemReference = stage { return true }
        return false
    }

    private let outputDirectory = URL(fileURLWithPath: "/tmp/playbacklab-hdr-probe", isDirectory: true)

    func run() async {
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )

            await playback.open(
                PlaybackModel.defaultVideoURL,
                startTime: PlaybackModel.knownOverexposureTime,
                startsPaused: true
            )
            try await waitUntilReady()
            try await Task.sleep(for: .seconds(2))
            try writeRendererSnapshot()
            try await captureWindow(named: "realitykit")

            playback.close()
            await playback.prepareSystemReference()
            playback.videoEntity.components.set(
                VideoPlayerComponent(avPlayer: playback.systemReferencePlayer)
            )
            stage = .realityKitAVPlayer
            try await Task.sleep(for: .seconds(2))
            try await captureWindow(named: "realitykit-avplayer")

            playback.videoEntity.components.remove(VideoPlayerComponent.self)
            stage = .systemReference
            try await Task.sleep(for: .seconds(2))
            try await captureWindow(named: "system-reference")

            playback.close()
            NSApp.terminate(nil)
        } catch {
            stage = .failed(error.localizedDescription)
            try? error.localizedDescription.write(
                to: outputDirectory.appendingPathComponent("error.txt"),
                atomically: true,
                encoding: .utf8
            )
            fputs("[DEBUG-HDR-VISUAL] \(error.localizedDescription)\n", stderr)
            NSApp.terminate(nil)
        }
    }

    private func waitUntilReady() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            switch playback.status {
            case .paused:
                return
            case .failed(let message):
                throw HDRVisualProbeError.playbackFailed(message)
            default:
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        throw HDRVisualProbeError.timedOut
    }

    private func captureWindow(named name: String) async throws {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else {
            throw HDRVisualProbeError.cannotCaptureWindow
        }
        let image = try await SCScreenshotManager.captureImage(in: window.frame)

        let url = outputDirectory.appendingPathComponent("\(name).png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw HDRVisualProbeError.cannotCreateImageDestination
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HDRVisualProbeError.cannotWriteImage
        }
        fputs("[DEBUG-HDR-VISUAL] captured \(url.path)\n", stderr)
    }

    private func writeRendererSnapshot() throws {
        var snapshot: [String: Any] = [
            "binding": playback.realityKitBindingSnapshot()
        ]
        if let buffer = playback.rendererDisplayedPixelBuffer() {
            let attachments = CVBufferCopyAttachments(buffer, .shouldPropagate) as? [String: Any] ?? [:]
            snapshot["displayedPixelBuffer"] = [
                "pixelFormat": fourCC(CVPixelBufferGetPixelFormatType(buffer)),
                "color": [
                    "primaries": value(attachments[kCVImageBufferColorPrimariesKey as String]),
                    "transfer": value(attachments[kCVImageBufferTransferFunctionKey as String]),
                    "matrix": value(attachments[kCVImageBufferYCbCrMatrixKey as String])
                ],
                "iosurfaceContentHeadroom": contentHeadroom(buffer),
                "planeSHA256": try planeSHA256(buffer)
            ]
        } else {
            snapshot["displayedPixelBuffer"] = "notExposed"
        }
        let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outputDirectory.appendingPathComponent("renderer-boundary.json"))
    }

    private func planeSHA256(_ buffer: CVPixelBuffer) throws -> [String] {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange else {
            return ["unsupported"]
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        return try (0..<CVPixelBufferGetPlaneCount(buffer)).map { plane in
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else {
                throw HDRVisualProbeError.missingPlane
            }
            let width = CVPixelBufferGetWidthOfPlane(buffer, plane)
            let height = CVPixelBufferGetHeightOfPlane(buffer, plane)
            let sourceRowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
            let logicalRowBytes = width * (plane == 0 ? 2 : 4)
            var data = Data(capacity: logicalRowBytes * height)
            for row in 0..<height {
                data.append(
                    base.advanced(by: row * sourceRowBytes).assumingMemoryBound(to: UInt8.self),
                    count: logicalRowBytes
                )
            }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    private func contentHeadroom(_ buffer: CVPixelBuffer) -> String {
        guard let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue(),
              let headroom = IOSurfaceCopyValue(surface, kIOSurfaceContentHeadroom) else {
            return "missing"
        }
        return String(describing: headroom)
    }

    private func value(_ value: Any?) -> String {
        value.map { String(describing: $0) } ?? "missing"
    }

    private func fourCC(_ value: OSType) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? String(format: "0x%08X", value)
    }
}

private enum HDRVisualProbeError: LocalizedError {
    case playbackFailed(String)
    case timedOut
    case cannotCaptureWindow
    case cannotCreateImageDestination
    case cannotWriteImage
    case missingPlane

    var errorDescription: String? {
        switch self {
        case .playbackFailed(let message): "Playback failed: \(message)"
        case .timedOut: "Timed out waiting for the RealityKit frame."
        case .cannotCaptureWindow: "Could not capture the diagnostic window."
        case .cannotCreateImageDestination: "Could not create the PNG destination."
        case .cannotWriteImage: "Could not write the diagnostic PNG."
        case .missingPlane: "The displayed pixel buffer has a missing plane."
        }
    }
}
