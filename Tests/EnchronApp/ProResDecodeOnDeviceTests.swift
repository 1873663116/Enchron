import AVFoundation
import CoreMedia
import Foundation
import Testing
import VideoToolbox

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
    #expect(started == false)
    #expect(decodedFrames == 0)
    #expect(reader.status == .failed)
}
