import AVFoundation
import ScreenCaptureKit

struct CaptureError: Error, CustomStringConvertible {
    let description: String
}

extension CMSampleBuffer {
    func pcmBuffer() -> AVAudioPCMBuffer? {
        try? withAudioBufferList { list, _ in
            guard let description = formatDescription?.audioStreamBasicDescription else { return nil }
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = description.mChannelsPerFrame == 1
                ? kAudioChannelLayoutTag_Mono
                : kAudioChannelLayoutTag_Stereo
            var streamDescription = description
            guard let format = AVAudioFormat(streamDescription: &streamDescription, channelLayout: AVAudioChannelLayout(layout: &layout)) else {
                return nil
            }
            return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer)
        }
    }
}

final class AudioSink: NSObject, SCStreamOutput {
    private let url: URL
    private var file: AVAudioFile?
    private(set) var frames: AVAudioFramePosition = 0
    private let lock = NSLock()

    init(url: URL) {
        self.url = url
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        file = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let buffer = sampleBuffer.pcmBuffer() else { return }
        lock.lock()
        defer { lock.unlock() }
        do {
            if file == nil {
                file = try AVAudioFile(
                    forWriting: url,
                    settings: [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: buffer.format.sampleRate,
                        AVNumberOfChannelsKey: buffer.format.channelCount,
                        AVLinearPCMBitDepthKey: 32,
                        AVLinearPCMIsFloatKey: true,
                        AVLinearPCMIsNonInterleaved: false,
                    ]
                )
            }
            try file?.write(from: buffer)
            frames += AVAudioFramePosition(buffer.frameLength)
        } catch {
            FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2, let seconds = Double(arguments[0]) else {
    FileHandle.standardError.write(Data("usage: audio_capture.swift <seconds> <output.wav>\n".utf8))
    exit(2)
}
let destination = URL(fileURLWithPath: arguments[1])
try? FileManager.default.removeItem(at: destination)

let done = DispatchSemaphore(value: 0)
var failure: String?
let sink = AudioSink(url: destination)

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw CaptureError(description: "no display available to attach the audio tap to")
        }
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = false
        configuration.sampleRate = 48000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: DispatchQueue(label: "audio"))
        try await stream.startCapture()
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        try await stream.stopCapture()
        sink.finish()
    } catch {
        failure = "\(error)"
    }
    done.signal()
}

done.wait()

if let failure {
    FileHandle.standardError.write(Data((failure + "\n").utf8))
    exit(1)
}
print("frames=\(sink.frames) path=\(destination.path)")
