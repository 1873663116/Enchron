@preconcurrency import AVFoundation
import Foundation

public struct AudioSpectrumFrame: Equatable, Sendable {
    public let presentationTimeSeconds: Double
    public let bands: [Float]

    public init(presentationTimeSeconds: Double, bands: [Float]) {
        self.presentationTimeSeconds = presentationTimeSeconds
        self.bands = bands
    }

    public static let silent = AudioSpectrumFrame(
        presentationTimeSeconds: 0,
        bands: Array(repeating: 0, count: AudioSpectrumAnalyzer.bandCount)
    )
}

final class AudioSpectrumAnalyzer: @unchecked Sendable {
    static let bandCount = 24

    private let queue = DispatchQueue(
        label: "com.enchron.playbackcore.audio-spectrum",
        qos: .userInteractive
    )
    private let stateLock = NSLock()
    private var isAnalysisPending = false
    private var lastSubmittedTime = -Double.infinity
    private var generation: UInt64 = 0
    private let minimumFrameInterval = 1.0 / 30.0

    func submit(
        _ sampleBuffer: CMSampleBuffer,
        presentationTime: CMTime,
        handler: @escaping @Sendable (AudioSpectrumFrame) -> Void
    ) {
        guard presentationTime.isNumeric,
              let samples = Self.copyMonoFloatSamples(from: sampleBuffer, limit: 512),
              samples.count >= 32 else { return }
        let presentationTimeSeconds = presentationTime.seconds
        let submissionGeneration = stateLock.withLock { () -> UInt64? in
            guard !isAnalysisPending,
                  presentationTimeSeconds - lastSubmittedTime >= minimumFrameInterval else {
                return nil
            }
            isAnalysisPending = true
            lastSubmittedTime = presentationTimeSeconds
            return generation
        }
        guard let submissionGeneration else { return }
        queue.async { [weak self] in
            let frame = AudioSpectrumFrame(
                presentationTimeSeconds: presentationTimeSeconds,
                bands: Self.analyze(samples)
            )
            let shouldPublish = self?.stateLock.withLock { () -> Bool in
                guard self?.generation == submissionGeneration else { return false }
                self?.isAnalysisPending = false
                return true
            } ?? false
            if shouldPublish { handler(frame) }
        }
    }

    func reset() {
        stateLock.withLock {
            generation &+= 1
            isAnalysisPending = false
            lastSubmittedTime = -Double.infinity
        }
    }

    static func analyze(_ samples: [Float]) -> [Float] {
        guard samples.count >= 2 else { return Array(repeating: 0, count: bandCount) }
        let count = samples.count
        let upperFrequencyRatio = 0.45
        let lowerFrequencyRatio = 2.0 / Double(count)
        return (0..<bandCount).map { band in
            let progress = Double(band) / Double(max(1, bandCount - 1))
            let frequency = lowerFrequencyRatio
                * pow(upperFrequencyRatio / lowerFrequencyRatio, progress)
            var real = 0.0
            var imaginary = 0.0
            for index in samples.indices {
                let window = 0.5 - 0.5 * cos(
                    2 * Double.pi * Double(index) / Double(count - 1)
                )
                let phase = 2 * Double.pi * frequency * Double(index)
                let value = Double(samples[index]) * window
                real += value * cos(phase)
                imaginary -= value * sin(phase)
            }
            let magnitude = hypot(real, imaginary) / Double(count)
            return Float(min(1, max(0, log10(1 + magnitude * 80))))
        }
    }

    private static func copyMonoFloatSamples(
        from sampleBuffer: CMSampleBuffer,
        limit: Int
    ) -> [Float]? {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format),
              description.pointee.mFormatID == kAudioFormatLinearPCM,
              description.pointee.mBitsPerChannel == 32,
              description.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        let channelCount = max(1, Int(description.pointee.mChannelsPerFrame))
        let frameCount = min(limit, CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0 else { return nil }
        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        ) == noErr,
        let dataPointer,
        totalLength >= frameCount * channelCount * MemoryLayout<Float>.size else {
            return nil
        }
        let floats = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
        return (0..<frameCount).map { frame in
            let base = frame * channelCount
            let total = (0..<channelCount).reduce(Float.zero) { sum, channel in
                sum + floats[base + channel]
            }
            return total / Float(channelCount)
        }
    }
}

extension SampleBufferPlaybackSession {
    func enqueueAudioSpectrumFrame(_ frame: AudioSpectrumFrame) {
        audioSpectrumFramesLock.withLock {
            audioSpectrumFrames.append(frame)
            if audioSpectrumFrames.count > 90 {
                audioSpectrumFrames.removeFirst(audioSpectrumFrames.count - 90)
            }
        }
    }

    func publishAudioSpectrumFrame(at time: CMTime) {
        guard mediaKind == .audioOnly, time.isNumeric else { return }
        let frame = audioSpectrumFramesLock.withLock { () -> AudioSpectrumFrame? in
            guard let index = audioSpectrumFrames.lastIndex(where: {
                $0.presentationTimeSeconds <= time.seconds + 0.03
            }) else { return nil }
            let frame = audioSpectrumFrames[index]
            if index > 0 {
                audioSpectrumFrames.removeFirst(index)
            }
            return frame
        }
        if let frame { onAudioSpectrumFrameChange?(frame) }
    }

    func resetAudioSpectrum() {
        audioSpectrumAnalyzer.reset()
        audioSpectrumFramesLock.withLock { audioSpectrumFrames.removeAll(keepingCapacity: true) }
        onAudioSpectrumFrameChange?(.silent)
    }
}
