import SwiftUI
import RealityKit

public struct MainView: View {
    @Environment(AppModel.self) var appModel
    @Environment(WindowVideoViewModel.self) var windowVideoViewModel

    public init() {}
    
    public var body: some View {
        ZStack {
            AppTabView()
            
            if appModel.isPlaying && appModel.playbackMode == .window {
                ZStack(alignment: .topTrailing) {
                    WindowVideoView(viewModel: windowVideoViewModel)
                        .glassBackgroundEffect()
                    
                    Button {
                        windowVideoViewModel.stop()
                        appModel.stopPlayback()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                }
                .padding()
            }
        }
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { windowVideoViewModel.lastErrorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        windowVideoViewModel.lastErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                windowVideoViewModel.lastErrorMessage = nil
            }
        } message: {
            Text(windowVideoViewModel.lastErrorMessage ?? "Unknown playback error")
        }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            if appModel.isPlaying {
                PlayerControlsView()
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    MainView()
        .environment(AppModel())
}
