import SwiftUI

public struct PlaybackMenuView: View {
    let onDismiss: () -> Void
    
    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 40) {
                VStack {
                    Image(systemName: "captions.bubble")
                        .font(.largeTitle)
                    Text("Subtitles")
                }
                
                VStack {
                    Image(systemName: "waveform")
                        .font(.largeTitle)
                    Text("Audio")
                }
                
                VStack {
                    Image(systemName: "speedometer")
                        .font(.largeTitle)
                    Text("Speed")
                }
            }
            .padding(40)
            .glassBackgroundEffect()
        }
        .onAppear {
            // Auto-dismiss after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                onDismiss()
            }
        }
    }
}
