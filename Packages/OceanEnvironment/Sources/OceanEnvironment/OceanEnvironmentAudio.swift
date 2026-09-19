import AVFAudio
import EnvironmentSceneContract
import Foundation
import RealityKit
import simd

@MainActor
final class OceanEnvironmentAudio {
    static let audioDirectoryName = "Audio"
    static let ambientFileName = "ocean_ambient_quad_4min"
    static let swellBandPrefixes = ["ocean_swell_near", "ocean_swell_mid", "ocean_swell_far"]
    static let bandDistances: [ClosedRange<Float>] = [6...14, 14...35, 35...80]
    static let bandWeights: [Float] = [0.3, 0.4, 0.3]
    static let fadeDuration: TimeInterval = 1.5
    static let ambientGainDecibels: Double = 0
    static let sourceCount = 6
    static let periodJitter: ClosedRange<Double> = 0.8...1.2
    static let secondSwellChance: Float = 0.3
    static let playsSwells = false

    let swellPeriod: TimeInterval
    private weak var root: Entity?
    private var ambientEntity: Entity?
    private var ambientResource: AudioFileResource?
    private var ambientController: AudioPlaybackController?
    private var swellGroups: [AudioFileGroupResource?] = []
    private var sources: [Entity] = []
    private var nextSource = 0
    private var swellControllers: [AudioPlaybackController] = []
    private var scheduler: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    private var isVideoPlaying = false
    private var isStarted = false
    private var interruptionObserver: NSObjectProtocol?
    private var generator = SystemRandomNumberGenerator()

    init(swellWavelength: Float, waterDepth: Float) {
        swellPeriod = Self.period(wavelength: swellWavelength, depth: waterDepth)
    }

    static func period(wavelength: Float, depth: Float) -> TimeInterval {
        let waveNumber = 2 * Float.pi / max(wavelength, 0.01)
        let angularFrequency = (9.81 * waveNumber * tanh(waveNumber * max(depth, 0.01))).squareRoot()
        return TimeInterval(2 * Float.pi / angularFrequency)
    }

    func prepare(in root: Entity, restPose: EnvironmentScreenRestPose, bundle: Bundle) async {
        scheduler?.cancel()
        scheduler = nil
        pauseTask?.cancel()
        pauseTask = nil
        ambientController?.stop()
        ambientController = nil
        for controller in swellControllers {
            controller.stop()
        }
        swellControllers.removeAll()
        sources.removeAll()
        nextSource = 0
        isStarted = false
        isVideoPlaying = false
        self.root = root
        let ambient = Self.firstAmbientEntity(in: root) ?? Self.makeAmbientEntity(in: root)
        ambient.setOrientation(simd_quatf(angle: restPose.yawRadians, axis: [0, 1, 0]), relativeTo: nil)
        ambientEntity = ambient
        installInterruptionObserver()
        guard let directory = bundle.url(forResource: Self.audioDirectoryName, withExtension: nil) else { return }
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let url = files.first(where: { $0.deletingPathExtension().lastPathComponent == Self.ambientFileName }) {
            var configuration = AudioFileResource.Configuration()
            configuration.shouldLoop = true
            configuration.loadingStrategy = .stream
            ambientResource = try? await AudioFileResource(
                contentsOf: url,
                withName: Self.ambientFileName,
                configuration: configuration
            )
        }
        guard Self.playsSwells else { return }
        var configuration = AudioFileResource.Configuration()
        configuration.loadingStrategy = .preload
        var groups: [AudioFileGroupResource?] = []
        for prefix in Self.swellBandPrefixes {
            var members: [AudioFileResource] = []
            for url in files where url.lastPathComponent.hasPrefix(prefix) {
                if let member = try? await AudioFileResource(
                    contentsOf: url,
                    withName: url.deletingPathExtension().lastPathComponent,
                    configuration: configuration
                ) {
                    members.append(member)
                }
            }
            groups.append(members.isEmpty ? nil : try? AudioFileGroupResource(members))
        }
        swellGroups = groups
        guard swellGroups.contains(where: { $0 != nil }) else { return }
        for _ in 0..<Self.sourceCount {
            let source = Entity()
            source.components.set(SpatialAudioComponent(
                gain: 0,
                directLevel: 0,
                reverbLevel: -6,
                directivity: .beam(focus: 0),
                distanceAttenuation: .rolloff(factor: 0.5)
            ))
            root.addChild(source)
            sources.append(source)
        }
    }

    func startIfNeeded() {
        guard !isStarted, !isVideoPlaying else { return }
        fadeIn()
    }

    func setVideoPlaying(_ playing: Bool) {
        let changed = playing != isVideoPlaying
        isVideoPlaying = playing
        if playing {
            if changed {
                fadeOut()
            }
        } else if changed || !isStarted {
            fadeIn()
        }
    }

    private static func firstAmbientEntity(in entity: Entity) -> Entity? {
        if entity.components.has(AmbientAudioComponent.self) {
            return entity
        }
        for child in entity.children {
            if let found = firstAmbientEntity(in: child) {
                return found
            }
        }
        return nil
    }

    private static func makeAmbientEntity(in root: Entity) -> Entity {
        let entity = Entity()
        entity.components.set(AmbientAudioComponent())
        root.addChild(entity)
        return entity
    }

    /// visionOS interrupts the app's audio when its last window closes even
    /// though the immersive space keeps running; re-arm the ambient loop once
    /// the interruption ends.
    private func installInterruptionObserver() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .ended
            else { return }
            Task { @MainActor in
                self?.resumeAmbientAfterInterruption()
            }
        }
    }

    private func resumeAmbientAfterInterruption() {
        guard isStarted, !isVideoPlaying, let ambientController else { return }
        if !ambientController.isPlaying {
            ambientController.gain = -.infinity
        }
        ambientController.play()
        ambientController.fade(to: Self.ambientGainDecibels, duration: Self.fadeDuration)
    }

    private func fadeIn() {
        guard let root, root.scene != nil else { return }
        isStarted = true
        pauseTask?.cancel()
        pauseTask = nil
        if let ambientEntity, let ambientResource {
            let controller = ambientController ?? ambientEntity.prepareAudio(ambientResource)
            ambientController = controller
            if !controller.isPlaying {
                controller.gain = -.infinity
                controller.play()
            }
            controller.fade(to: Self.ambientGainDecibels, duration: Self.fadeDuration)
        }
        startScheduler()
    }

    private func fadeOut() {
        scheduler?.cancel()
        scheduler = nil
        ambientController?.fade(to: -.infinity, duration: Self.fadeDuration)
        for controller in swellControllers {
            controller.fade(to: -.infinity, duration: Self.fadeDuration)
        }
        pauseTask?.cancel()
        pauseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeDuration))
            guard !Task.isCancelled, let self, self.isVideoPlaying else { return }
            self.ambientController?.pause()
            for controller in self.swellControllers {
                controller.stop()
            }
            self.swellControllers.removeAll()
        }
    }

    private func startScheduler() {
        guard scheduler == nil, !sources.isEmpty else { return }
        scheduler = Task { @MainActor [weak self] in
            while let delay = self?.nextSwellDelay() {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, !self.isVideoPlaying, self.root?.scene != nil else { return }
                self.emitSwells()
            }
        }
    }

    private func nextSwellDelay() -> TimeInterval {
        swellPeriod * Double.random(in: Self.periodJitter, using: &generator)
    }

    private func emitSwells() {
        guard let root else { return }
        swellControllers.removeAll { !$0.isPlaying }
        let waterHeight = root.convert(position: .zero, to: nil).y
        let count = Float.random(in: 0...1, using: &generator) < Self.secondSwellChance ? 2 : 1
        for _ in 0..<count {
            let band = pickBand()
            guard let group = swellGroups[band] else { continue }
            let distance = Float.random(in: Self.bandDistances[band], using: &generator)
            let azimuth = Float.random(in: -Float.pi...Float.pi, using: &generator)
            let source = sources[nextSource]
            nextSource = (nextSource + 1) % sources.count
            source.setPosition([distance * sin(azimuth), waterHeight, -distance * cos(azimuth)], relativeTo: nil)
            let controller = source.prepareAudio(group)
            controller.gain = .zero
            controller.play()
            swellControllers.append(controller)
        }
    }

    private func pickBand() -> Int {
        let total = Self.bandWeights.reduce(0, +)
        var roll = Float.random(in: 0..<total, using: &generator)
        for (index, weight) in Self.bandWeights.enumerated() {
            if roll < weight {
                return index
            }
            roll -= weight
        }
        return Self.bandWeights.count - 1
    }
}
