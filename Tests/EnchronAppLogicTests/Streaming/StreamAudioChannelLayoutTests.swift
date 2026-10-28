import AVFAudio
import XCTest
@testable import GameStreaming

nonisolated final class StreamAudioChannelLayoutTests: XCTestCase {
    func testSurroundChannelCountsUseTheWaveLayoutsTheHostEncodes() {
        XCTAssertEqual(StreamAudioOutput.channelLayoutTag(channelCount: 2), kAudioChannelLayoutTag_Stereo)
        XCTAssertEqual(StreamAudioOutput.channelLayoutTag(channelCount: 6), kAudioChannelLayoutTag_WAVE_5_1_B)
        XCTAssertEqual(StreamAudioOutput.channelLayoutTag(channelCount: 8), kAudioChannelLayoutTag_WAVE_7_1)
    }

    func testTheMixerDownmixesTheNegotiatedSurroundLayoutsToAudibleStereo() throws {
        for channels in [6, 8] {
            let peak = try renderedPeak(channelCount: channels)
            XCTAssertGreaterThan(peak, 0.01, "channels=\(channels) rendered silence")
        }
    }

    private func renderedPeak(channelCount: Int) throws -> Float {
        let sampleRate = 48_000.0
        let tag = StreamAudioOutput.channelLayoutTag(channelCount: channelCount)
        let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: tag))
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            interleaved: false,
            channelLayout: layout
        )
        let engine = AVAudioEngine()
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0..<Int(frameCount) {
                    data[frame] = 0.5
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        let outputFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ))
        try engine.enableManualRenderingMode(.offline, format: outputFormat, maximumFrameCount: 1024)
        try engine.start()
        defer { engine.stop() }
        let output = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: 1024
        ))
        var peak: Float = 0
        for _ in 0..<10 {
            guard try engine.renderOffline(1024, to: output) == .success else { continue }
            guard let data = output.floatChannelData else { continue }
            for channel in 0..<Int(output.format.channelCount) {
                for frame in 0..<Int(output.frameLength) {
                    peak = max(peak, abs(data[channel][frame]))
                }
            }
        }
        return peak
    }
}
