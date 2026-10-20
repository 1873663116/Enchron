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

struct Options {
    var seconds: Double?
    var outputPath: String?
    var bundleIdentifier: String?
    var applicationName: String?
    var listApplications = false
}

let usage = "usage: audio_capture <seconds> <output.wav> [--app <bundle-id> | --app-name <name>]\n       audio_capture --list-apps"

func parseOptions(_ arguments: [String]) -> Options? {
    var options = Options()
    var index = 0
    func nextValue(_ flag: String) -> String? {
        guard index + 1 < arguments.count else {
            FileHandle.standardError.write(Data("missing value for \(flag)\n".utf8))
            return nil
        }
        index += 1
        return arguments[index]
    }
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--list-apps":
            options.listApplications = true
        case "--app":
            guard let value = nextValue(argument), !value.isEmpty else { return nil }
            options.bundleIdentifier = value
        case "--app-name":
            guard let value = nextValue(argument), !value.isEmpty else { return nil }
            options.applicationName = value
        default:
            if argument.hasPrefix("--") {
                FileHandle.standardError.write(Data("unknown argument \(argument)\n".utf8))
                return nil
            }
            if options.seconds == nil {
                guard let seconds = Double(argument), seconds > 0, seconds.isFinite else {
                    FileHandle.standardError.write(Data("seconds must be a finite positive number, not \(argument)\n".utf8))
                    return nil
                }
                options.seconds = seconds
            } else if options.outputPath == nil {
                options.outputPath = argument
            } else {
                FileHandle.standardError.write(Data("unexpected argument \(argument)\n".utf8))
                return nil
            }
        }
        index += 1
    }
    return options
}

func describe(_ application: SCRunningApplication) -> String {
    "bundle=\(application.bundleIdentifier) name=\(application.applicationName) pid=\(application.processID)"
}

func matches(_ application: SCRunningApplication, options: Options) -> Bool {
    if let wanted = options.bundleIdentifier, application.bundleIdentifier == wanted {
        return true
    }
    if let wanted = options.applicationName {
        if application.applicationName == wanted {
            return true
        }
        if application.applicationName.lowercased().contains(wanted.lowercased()) {
            return true
        }
    }
    return false
}

func contentFilter(
    display: SCDisplay,
    options: Options,
    content: SCShareableContent
) throws -> SCContentFilter {
    guard options.bundleIdentifier != nil || options.applicationName != nil else {
        return SCContentFilter(display: display, excludingWindows: [])
    }
    let candidates = content.applications.filter { matches($0, options: options) }
    guard let application = candidates.first else {
        let wanted = options.bundleIdentifier ?? options.applicationName ?? ""
        let running = content.applications.map(describe).sorted().joined(separator: "\n  ")
        throw CaptureError(
            description: "no running application matches \(wanted); --list-apps lists:\n  \(running)"
        )
    }
    if candidates.count > 1 {
        FileHandle.standardError.write(Data("several applications match; capturing \(describe(application))\n".utf8))
    }
    return SCContentFilter(display: display, including: [application], exceptingWindows: [])
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let options = parseOptions(arguments) else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
guard options.listApplications || (options.seconds != nil && options.outputPath != nil) else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
let durationSeconds = options.seconds ?? 0
let destination = URL(fileURLWithPath: options.outputPath ?? "")
if !options.listApplications {
    try? FileManager.default.removeItem(at: destination)
}

let done = DispatchSemaphore(value: 0)
var failure: String?
let sink = AudioSink(url: destination)

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        if options.listApplications {
            for application in content.applications.sorted(by: { $0.bundleIdentifier < $1.bundleIdentifier }) {
                print(describe(application))
            }
            done.signal()
            return
        }
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

        let filter = try contentFilter(display: display, options: options, content: content)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: DispatchQueue(label: "audio"))
        try await stream.startCapture()
        try await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))
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
if options.listApplications {
    exit(0)
}
print("frames=\(sink.frames) path=\(destination.path)")
