import AVFoundation
import CoreMedia
import CoreVideo
import Dispatch
import Metal
import PlaybackPresentation
import RealityKit
import XCTest
@testable import Enchron

private nonisolated final class ReadyVideoReceiver: @unchecked Sendable {
    private let receiver: AVSampleBufferVideoRenderer.Receiver

    init(receiver: consuming AVSampleBufferVideoRenderer.Receiver) {
        self.receiver = receiver
    }

    func enqueueImmediately(
        _ sample: sending CMReadySampleBuffer<CMSampleBuffer.DynamicContent>
    ) -> AVSampleBufferVideoRenderer.Receiver.EnqueueResult {
        receiver.enqueueImmediately(sample)
    }
}

nonisolated final class PlaybackRealityPresenterTests: XCTestCase {
    @MainActor
    func testDockingWorldCanLoadFromProductResources() async throws {
        let world = try await Entity(named: EnvironmentSceneMapping.worldSceneName)
        let anchor = try PlaybackSurfaceAnchorResolver.resolve(in: world)

        XCTAssertFalse(world.name.isEmpty)
        XCTAssertEqual(anchor.name, PlaybackSurfaceAnchorResolver.canonicalName)
        XCTAssertNil(anchor.components[ModelComponent.self])
        XCTAssertTrue(anchor.children.allSatisfy { $0.components[ModelComponent.self] == nil })
    }

    @MainActor
    func testLegacyPlaybackSurfaceIsMigratedAndStrippedOfGeometry() throws {
        let world = Entity()
        let legacy = ModelEntity(
            mesh: .generatePlane(width: 1, depth: 1),
            materials: [SimpleMaterial()]
        )
        legacy.name = PlaybackSurfaceAnchorResolver.legacyName
        let legacyChild = ModelEntity(
            mesh: .generatePlane(width: 1, depth: 1),
            materials: [SimpleMaterial()]
        )
        legacy.addChild(legacyChild)
        world.addChild(legacy)

        let anchor = try PlaybackSurfaceAnchorResolver.resolve(in: world)

        XCTAssertTrue(anchor === legacy)
        XCTAssertEqual(anchor.name, PlaybackSurfaceAnchorResolver.canonicalName)
        XCTAssertNil(anchor.components[ModelComponent.self])
        XCTAssertNil(legacyChild.components[ModelComponent.self])
    }

    @MainActor
    func testRealityRendererRendersVideoPlayerComponentFromAReadySampleBuffer() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this test host.")
        }
        let videoRenderer = AVSampleBufferVideoRenderer()
        let synchronizer = AVSampleBufferRenderSynchronizer()
        let receiver = ReadyVideoReceiver(
            receiver: synchronizer.sampleBufferReceiver(adding: videoRenderer)
        )
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 256,
            height: 256,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .color(
            CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        )
        let camera = Entity()
        camera.components.set(PerspectiveCameraComponent())
        renderer.activeCamera = camera
        renderer.entities.append(camera)
        let videoEntity = Entity()
        videoEntity.position.z = -1
        PlaybackRealityPresenter.configure(
            videoEntity,
            renderer: videoRenderer,
            presentation: .window,
            stereoLayout: .mono
        )
        renderer.entities.append(videoEntity)
        let enqueueResult = receiver.enqueueImmediately(
            try Self.makeSolidGreenReadySampleBuffer()
        )
        switch enqueueResult {
        case .enqueued, .enqueuedWithDecodeFailures:
            break
        case .cancelledDueToFlush:
            XCTFail("The video sample was cancelled by a flush.")
        case .cancelledDueToFlushRequiredToResume(let error):
            XCTFail("The video renderer required a flush: \(error.localizedDescription)")
        case .cancelledDueToError(let error):
            XCTFail("The video renderer rejected the sample: \(error.localizedDescription)")
        @unknown default:
            XCTFail("The video renderer returned an unknown enqueue result.")
        }
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        for frame in 0..<3 {
            let rendered = DispatchSemaphore(value: 0)
            try renderer.updateAndRender(
                deltaTime: 1.0 / 60.0,
                cameraOutput: output,
                onComplete: { _ in rendered.signal() }
            )
            guard rendered.wait(timeout: .now() + 5) == .success else {
                XCTFail("RealityRenderer did not complete frame \(frame).")
                return
            }
        }

        var bytes = [UInt8](repeating: 0, count: 256 * 256 * 4)
        texture.getBytes(
            &bytes,
            bytesPerRow: 256 * 4,
            from: MTLRegionMake2D(0, 0, 256, 256),
            mipmapLevel: 0
        )
        let center = averageColor(in: bytes, width: 256, xRange: 96..<160, yRange: 96..<160)
        XCTAssertGreaterThan(center.green, center.red * 2)
        XCTAssertGreaterThan(center.green, center.blue * 2)
        _ = synchronizer
        _ = receiver
    }

    @MainActor
    func testWindowBindsTheActiveRendererToVideoPlayerComponent() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let entity = Entity()

        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            stereoLayout: .mono
        )

        XCTAssertTrue(PlaybackRealityPresenter.isBound(entity, to: renderer, presentation: .window))
        XCTAssertNil(entity.components[ModelComponent.self])
        let component = try XCTUnwrap(entity.components[VideoPlayerComponent.self])
        XCTAssertTrue(component.videoRenderer === renderer)
        XCTAssertEqual(component.desiredViewingMode, .mono)
        XCTAssertEqual(component.desiredImmersiveViewingMode, .portal)
    }

    @MainActor
    func testRepeatedWindowConfigurationReusesTheExistingVideoPlayerComponent() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let entity = Entity()
        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            stereoLayout: .mono
        )
        let firstComponent = try XCTUnwrap(entity.components[VideoPlayerComponent.self])

        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            stereoLayout: .sideBySide
        )

        let component = try XCTUnwrap(entity.components[VideoPlayerComponent.self])
        XCTAssertTrue(component.videoRenderer === firstComponent.videoRenderer)
        XCTAssertTrue(component.videoRenderer === renderer)
        XCTAssertEqual(component.desiredViewingMode, .stereo)
        XCTAssertEqual(component.desiredImmersiveViewingMode, .portal)
    }

    @MainActor
    func testPanoramaMovesTheSameRendererToVideoPlayerComponent() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let entity = Entity()
        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            stereoLayout: .mono
        )

        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .panorama,
            stereoLayout: .sideBySide
        )

        XCTAssertTrue(PlaybackRealityPresenter.isBound(entity, to: renderer, presentation: .panorama))
        XCTAssertNil(entity.components[ModelComponent.self])
        let component = try XCTUnwrap(entity.components[VideoPlayerComponent.self])
        XCTAssertTrue(component.videoRenderer === renderer)
        XCTAssertEqual(component.desiredViewingMode, .stereo)
        XCTAssertEqual(component.desiredImmersiveViewingMode, .progressive)
    }

    private nonisolated static func makeSolidGreenReadySampleBuffer() throws
        -> CMReadySampleBuffer<CMSampleBuffer.DynamicContent>
    {
        let attributes: CFDictionary = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
        ] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        let pixelStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            64,
            kCVPixelFormatType_32BGRA,
            attributes,
            &pixelBuffer
        )
        guard pixelStatus == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(pixelStatus))
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        guard let rawBaseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kCVReturnInvalidArgument))
        }
        let baseAddress = rawBaseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<64 {
            for x in 0..<64 {
                let offset = y * bytesPerRow + x * 4
                baseAddress[offset] = 0
                baseAddress[offset + 1] = 255
                baseAddress[offset + 2] = 0
                baseAddress[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(formatStatus))
        }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(sampleStatus))
        }
        return CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(unsafeBuffer: sampleBuffer)
    }

    private func averageColor(
        in bytes: [UInt8],
        width: Int,
        xRange: Range<Int>,
        yRange: Range<Int>
    ) -> (blue: Double, green: Double, red: Double) {
        var blue = 0.0
        var green = 0.0
        var red = 0.0
        for y in yRange {
            for x in xRange {
                let offset = (y * width + x) * 4
                blue += Double(bytes[offset])
                green += Double(bytes[offset + 1])
                red += Double(bytes[offset + 2])
            }
        }
        let count = Double(xRange.count * yRange.count)
        return (blue / count, green / count, red / count)
    }
}
