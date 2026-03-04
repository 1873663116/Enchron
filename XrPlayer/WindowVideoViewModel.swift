import Foundation
import Observation
import MetalKit
import QuartzCore

@MainActor
@Observable
public final class WindowVideoViewModel {
    public var playbackState: PlaybackCoreDomain.PlaybackState = .idle
    public var playbackPosition: PlaybackCoreDomain.PlaybackPosition = .init(seconds: 0, duration: 0)
    public var lastErrorMessage: String?
    public let usesNativeGPUOutput: Bool
    
    // Metal renderer
    public let renderer: MetalVideoRenderer?
    
    // Dependencies
    private let player: PlaybackControlling
    private var statusTask: Task<Void, Never>?
    
    public init(player: PlaybackControlling) {
        self.player = player
        if let adapter = player as? MPVPlayerAdapter {
            self.usesNativeGPUOutput = adapter.usesNativeGPUOutput
        } else {
            self.usesNativeGPUOutput = false
        }

        if self.usesNativeGPUOutput == false, let device = MTLCreateSystemDefaultDevice() {
            self.renderer = MetalVideoRenderer(device: device)
        } else {
            self.renderer = nil
        }

        // Wire up FrameOutput after all properties are initialized
        if let adapter = player as? MPVPlayerAdapter {
            adapter.frameOutput = renderer
            adapter.onRuntimeError = { [weak self] message in
                self?.playbackState = .failed
                self?.lastErrorMessage = message
            }
        }

        startStatusTask()
    }

    private func startStatusTask() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            while Task.isCancelled == false {
                await MainActor.run { [weak self] in
                    self?.updateStatus()
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
    
    private func updateStatus() {
        self.playbackState = player.currentState
        self.playbackPosition = player.currentPosition
    }
    
    public func play(url: URL) async throws {
        do {
            try await player.play(url: url)
            lastErrorMessage = nil
        } catch {
            self.playbackState = .failed
            self.lastErrorMessage = error.localizedDescription
            print("Failed to play: \(error.localizedDescription)")
            throw error
        }
    }
    
    public func pause() {
        player.pause()
    }
    
    public func resume() {
        player.resume()
    }
    
    public func stop() {
        player.stop()
        lastErrorMessage = nil
    }

    public func attachVideoLayer(_ layer: CAMetalLayer?) {
        (player as? MPVPlayerAdapter)?.attachVideoLayer(layer)
    }
}
