import AVFAudio
import Foundation
import Synchronization

final class StreamAudioOutput: @unchecked Sendable {
    struct Stats {
        var bufferedMilliseconds: Double
        var underruns: Int64
        var overflowFrames: Int64
        var trimmedFrames: Int64
        var engineRunning: Bool
        var engineStarts: Int64
    }

    private static let capacitySeconds = 0.100
    private static let primeSeconds = 0.020
    private static let trimAboveSeconds = 0.060
    private static let trimToSeconds = 0.030

    static func channelLayoutTag(channelCount: Int) -> AudioChannelLayoutTag {
        switch channelCount {
        case 2: kAudioChannelLayoutTag_Stereo
        case 6: kAudioChannelLayoutTag_WAVE_5_1_B
        case 8: kAudioChannelLayoutTag_WAVE_7_1
        default: kAudioChannelLayoutTag_DiscreteInOrder | AudioChannelLayoutTag(channelCount)
        }
    }

    private let ring = StreamAudioRing()
    private let queue = DispatchQueue(label: "app.enchron.stream-session.audio-output")
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var configuredFormat: (sampleRate: Int, channels: Int)?
    private var observers: [NSObjectProtocol] = []
    private var stopped = false
    private let engineStarts = Atomic<Int64>(0)
    private let engineRunning = Atomic<Bool>(false)
    private let lastEngineRecoveryNanoseconds = Atomic<UInt64>(0)

    var onEvent: (@Sendable (String) -> Void)?

    func enqueue(pcm: Data, channels: Int, sampleRate: Int, frameCount: Int) {
        guard channels > 0, sampleRate > 0, frameCount > 0,
              pcm.count == frameCount * channels * MemoryLayout<Int16>.size else { return }
        if ring.format != (sampleRate, channels) {
            ring.configure(
                sampleRate: sampleRate,
                channels: channels,
                capacityFrames: Int(Double(sampleRate) * Self.capacitySeconds),
                primeFrames: Int(Double(sampleRate) * Self.primeSeconds),
                trimAboveFrames: Int(Double(sampleRate) * Self.trimAboveSeconds),
                trimToFrames: Int(Double(sampleRate) * Self.trimToSeconds)
            )
            queue.async { [weak self] in
                self?.configureEngine(sampleRate: sampleRate, channels: channels)
            }
        }
        pcm.withUnsafeBytes { raw in
            ring.write(raw.bindMemory(to: Int16.self), frames: frameCount)
        }
        recoverEngineIfStopped()
    }

    private func recoverEngineIfStopped() {
        guard !engineRunning.load(ordering: .relaxed) else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now &- lastEngineRecoveryNanoseconds.load(ordering: .relaxed) >= 1_000_000_000 else {
            return
        }
        lastEngineRecoveryNanoseconds.store(now, ordering: .relaxed)
        queue.async { [weak self] in
            guard let self, !self.stopped, self.sourceNode != nil, !self.engine.isRunning else {
                return
            }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                self.onEvent?("audio session reactivation failed error=\(error.localizedDescription)")
            }
            self.startEngine(reason: "framesWithoutEngine")
        }
    }

    func stats() -> Stats {
        let snapshot = ring.snapshot()
        return Stats(
            bufferedMilliseconds: snapshot.bufferedMilliseconds,
            underruns: snapshot.underruns,
            overflowFrames: snapshot.overflowFrames,
            trimmedFrames: snapshot.trimmedFrames,
            engineRunning: engineRunning.load(ordering: .relaxed),
            engineStarts: engineStarts.load(ordering: .relaxed)
        )
    }

    func stop() {
        queue.sync {
            stopped = true
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            engine.stop()
            engineRunning.store(false, ordering: .relaxed)
        }
    }

    private func configureEngine(sampleRate: Int, channels: Int) {
        guard !stopped else { return }
        guard configuredFormat.map({ $0 != (sampleRate, channels) }) ?? true else { return }
        let layout = AVAudioChannelLayout(
            layoutTag: Self.channelLayoutTag(channelCount: channels)
        )
        guard let layout else { return }
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            interleaved: false,
            channelLayout: layout
        )

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setPreferredSampleRate(Double(sampleRate))
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            onEvent?("audio session activation failed error=\(error.localizedDescription)")
        }

        if let sourceNode {
            engine.stop()
            engine.detach(sourceNode)
        }
        let ring = self.ring
        let node = AVAudioSourceNode(format: format) { isSilence, _, frameCount, bufferList in
            ring.read(
                into: UnsafeMutableAudioBufferListPointer(bufferList),
                frames: Int(frameCount),
                isSilence: isSilence
            )
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
        configuredFormat = (sampleRate, channels)
        installObservers()
        startEngine(reason: "configure")
        onEvent?(
            "audio output configured rate=\(sampleRate) channels=\(channels)"
                + " ioBuffer=\(session.ioBufferDuration) hwRate=\(session.sampleRate)"
        )
    }

    private func startEngine(reason: String) {
        guard !stopped, sourceNode != nil else { return }
        do {
            engine.prepare()
            try engine.start()
            engineStarts.wrappingAdd(1, ordering: .relaxed)
            engineRunning.store(true, ordering: .relaxed)
            onEvent?("audio engine start reason=\(reason)")
        } catch {
            engineRunning.store(false, ordering: .relaxed)
            onEvent?("audio engine start failed reason=\(reason) error=\(error.localizedDescription)")
        }
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.startEngine(reason: "configurationChange") }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawReason = notification.userInfo?["AVAudioSessionInterruptionReasonKey"] as? UInt
            self.onEvent?(
                "audio interruption type=\(rawType.map(String.init) ?? "none")"
                    + " reason=\(rawReason.map(String.init) ?? "none")"
            )
            guard rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended else {
                self.engineRunning.store(false, ordering: .relaxed)
                return
            }
            self.queue.async {
                try? AVAudioSession.sharedInstance().setActive(true)
                self.startEngine(reason: "interruptionEnded")
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                guard let format = self.configuredFormat else { return }
                self.configuredFormat = nil
                self.configureEngine(sampleRate: format.sampleRate, channels: format.channels)
            }
        })
    }
}

final class StreamAudioRing: @unchecked Sendable {
    struct Snapshot {
        var bufferedMilliseconds: Double
        var underruns: Int64
        var overflowFrames: Int64
        var trimmedFrames: Int64
    }

    private struct State {
        var storage: [Float] = []
        var sampleRate = 0
        var channels = 0
        var capacityFrames = 0
        var primeFrames = 0
        var readFrame = 0
        var bufferedFrames = 0
        var priming = true
        var trimAboveFrames = 0
        var trimToFrames = 0
        var underruns: Int64 = 0
        var overflowFrames: Int64 = 0
        var trimmedFrames: Int64 = 0
    }

    private let state = Mutex(State())

    var format: (Int, Int) {
        state.withLock { ($0.sampleRate, $0.channels) }
    }

    func configure(
        sampleRate: Int,
        channels: Int,
        capacityFrames: Int,
        primeFrames: Int,
        trimAboveFrames: Int,
        trimToFrames: Int
    ) {
        state.withLock { value in
            value = State()
            value.sampleRate = sampleRate
            value.channels = channels
            value.capacityFrames = max(capacityFrames, 1)
            value.primeFrames = min(primeFrames, value.capacityFrames)
            value.trimAboveFrames = min(trimAboveFrames, value.capacityFrames)
            value.trimToFrames = min(trimToFrames, value.trimAboveFrames)
            value.storage = [Float](repeating: 0, count: value.capacityFrames * channels)
        }
    }

    func write(_ samples: UnsafeBufferPointer<Int16>, frames: Int) {
        state.withLock { value in
            let channels = value.channels
            guard channels > 0, samples.count >= frames * channels else { return }
            let free = value.capacityFrames - value.bufferedFrames
            let accepted = min(frames, free)
            if accepted < frames {
                value.overflowFrames += Int64(frames - accepted)
            }
            guard accepted > 0 else { return }
            var writeFrame = (value.readFrame + value.bufferedFrames) % value.capacityFrames
            value.storage.withUnsafeMutableBufferPointer { storage in
                for frame in 0..<accepted {
                    let source = frame * channels
                    let destination = writeFrame * channels
                    for channel in 0..<channels {
                        storage[destination + channel] = Float(samples[source + channel]) / 32768
                    }
                    writeFrame += 1
                    if writeFrame == value.capacityFrames { writeFrame = 0 }
                }
            }
            value.bufferedFrames += accepted
            if value.bufferedFrames > value.trimAboveFrames {
                let excess = value.bufferedFrames - value.trimToFrames
                value.readFrame = (value.readFrame + excess) % value.capacityFrames
                value.bufferedFrames = value.trimToFrames
                value.trimmedFrames += Int64(excess)
            }
            if value.priming, value.bufferedFrames >= value.primeFrames {
                value.priming = false
            }
        }
    }

    func read(
        into buffers: UnsafeMutableAudioBufferListPointer,
        frames: Int,
        isSilence: UnsafeMutablePointer<ObjCBool>
    ) {
        state.withLock { value in
            let channels = value.channels
            let available = value.priming ? 0 : min(frames, value.bufferedFrames)
            if available < frames, !value.priming, channels > 0 {
                value.underruns += 1
                value.priming = true
            }
            value.storage.withUnsafeBufferPointer { storage in
                for (channel, buffer) in buffers.enumerated() {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    var readFrame = value.readFrame
                    for frame in 0..<frames {
                        if frame < available, channel < channels {
                            data[frame] = storage[readFrame * channels + channel]
                            readFrame += 1
                            if readFrame == value.capacityFrames { readFrame = 0 }
                        } else {
                            data[frame] = 0
                        }
                    }
                }
            }
            if available > 0 {
                value.readFrame = (value.readFrame + available) % value.capacityFrames
                value.bufferedFrames -= available
            }
            isSilence.pointee = ObjCBool(available == 0)
        }
    }

    func snapshot() -> Snapshot {
        state.withLock { value in
            Snapshot(
                bufferedMilliseconds: value.sampleRate > 0
                    ? Double(value.bufferedFrames) * 1000 / Double(value.sampleRate)
                    : 0,
                underruns: value.underruns,
                overflowFrames: value.overflowFrames,
                trimmedFrames: value.trimmedFrames
            )
        }
    }
}
