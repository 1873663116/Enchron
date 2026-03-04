import SwiftUI

public struct PlayerControlsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WindowVideoViewModel.self) private var videoViewModel
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            // Timeline
            HStack(spacing: 12) {
                Text(formatTime(videoViewModel.playbackPosition.seconds))
                    .font(.caption2.monospacedDigit())
                
                Slider(
                    value: Binding(
                        get: { videoViewModel.playbackPosition.seconds },
                        set: { _ in } // Scrubbing logic would go here
                    ),
                    in: 0...max(videoViewModel.playbackPosition.duration, 1)
                )
                .tint(.accentColor)
                
                Text(formatTime(videoViewModel.playbackPosition.duration))
                    .font(.caption2.monospacedDigit())
            }
            .padding(.horizontal)
            
            // Buttons
            HStack(spacing: 30) {
                Button {
                    // Backward action
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                
                Button {
                    if videoViewModel.playbackState == .playing {
                        videoViewModel.pause()
                        appModel.updatePlaybackState(.paused)
                    } else {
                        videoViewModel.resume()
                        appModel.updatePlaybackState(.playing)
                    }
                } label: {
                    Image(systemName: videoViewModel.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                }
                .buttonStyle(.plain)
                
                Button {
                    // Forward action
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                
                Divider()
                    .frame(height: 30)
                
                Button {
                    videoViewModel.stop()
                    appModel.stopPlayback()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 500)
        .glassBackgroundEffect()
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}

#Preview {
    PlayerControlsView()
        .environment(AppModel())
}
