import Foundation
import CoreVideo
import Observation
import MetalKit

@MainActor
@Observable
public final class WindowVideoViewModel {
    public var playbackState: PlaybackCoreDomain.PlaybackState = .idle
    public var playbackPosition: PlaybackCoreDomain.PlaybackPosition = .init(seconds: 0, duration: 0)
    
    // Metal renderer
    public let renderer: MetalVideoRenderer?
    
    // To trigger view updates
    public var frameCount: UInt64 = 0
    
    // Dependencies
    private let player: PlaybackControlling
    nonisolated(unsafe) private var statusTimer: Timer?
    
    public init(player: PlaybackControlling) {
        self.player = player

        if let device = MTLCreateSystemDefaultDevice() {
            self.renderer = MetalVideoRenderer(device: device)
        } else {
            self.renderer = nil
        }

        // Wire up FrameOutput after all properties are initialized
        if let adapter = player as? MPVPlayerAdapter {
            adapter.frameOutput = self
        }
        
        startStatusTimer()
    }
    
    deinit {
        let timer = statusTimer
        timer?.invalidate()
    }
    
    private func startStatusTimer() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }
    }
    
    private func updateStatus() {
        self.playbackState = player.currentState
        self.playbackPosition = player.currentPosition
    }
    
    public func play(url: URL) async {
        do {
            try await player.play(url: url)
        } catch {
            print("Failed to play: \(error)")
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
    }
}

extension WindowVideoViewModel: FrameOutput {
    public nonisolated func didOutputFrame(_ pixelBuffer: CVPixelBuffer) {
        self.renderer?.enqueueFrame(pixelBuffer)
        
        Task { @MainActor in
            self.frameCount &+= 1
        }
    }
}
