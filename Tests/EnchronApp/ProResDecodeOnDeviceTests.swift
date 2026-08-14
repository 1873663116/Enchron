import AVFoundation
import CoreMedia
import Foundation
import Testing
import VideoToolbox

/// Whether this device decodes a real ProRes file, asked of AVFoundation and VideoToolbox
/// rather than of the renderer.
///
/// The sample buffer renderer accepts every ProRes sample and then reports
/// readyWithDecodeFailures with "Cannot Decode", which does not say whether the device
/// lacks a decoder or the rendering path will not take this codec. These cases separate
/// the two. The fixture is whatever the harness last pushed into the app container, so
/// the test reports its absence rather than failing on it.
private func pushedProResFixture() -> URL? {
    let inbox = URL.documentsDirectory.appending(path: "TestMediaInbox")
    let contents = try? FileManager.default.contentsOfDirectory(
        at: inbox,
        includingPropertiesForKeys: nil
    )
    return contents?.first { $0.lastPathComponent.hasPrefix("B001C001") }
}

@Test("AVFoundation cannot decode a real ProRes file on this device either")
func proResFailsThroughAVFoundation() async throws {
    guard let fixture = pushedProResFixture() else {
        try? "fixture absent".write(
            to: URL.documentsDirectory.appending(path: "prores-decode.txt"),
            atomically: true,
            encoding: .utf8
        )
        return
    }
    let asset = AVURLAsset(url: fixture)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let formats = try await track.load(.formatDescriptions)
    let format = try #require(formats.first)
    var report = "subtype=\(CMFormatDescriptionGetMediaSubType(format))"
        + " dimensions=\(CMVideoFormatDescriptionGetDimensions(format))"

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
    )
    reader.add(output)
    let started = reader.startReading()

    var decodedFrames = 0
    while decodedFrames < 5, let sample = output.copyNextSampleBuffer() {
        if CMSampleBufferGetImageBuffer(sample) != nil { decodedFrames += 1 }
    }
    report += "\ndecodedFrames=\(decodedFrames)"
        + "\nreaderStatus=\(reader.status.rawValue)"
        + "\nreaderError=\(reader.error?.localizedDescription ?? "none")"
    try? report.write(
        to: URL.documentsDirectory.appending(path: "prores-decode.txt"),
        atomically: true,
        encoding: .utf8
    )
    // The renderer error alone could not tell a missing decoder from a rendering
    // path that will not take this codec. AVAssetReader is neither, so its failure
    // places the limit in the device.
    #expect(started == false)
    #expect(decodedFrames == 0)
    #expect(reader.status == .failed)
}
