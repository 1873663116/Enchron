import PlaybackCore
import RealityKit
import SwiftUI
import UniformTypeIdentifiers

struct PlaybackVerificationView: View {
    @State private var model = PlaybackVerificationModel()
    @State private var isImporting = false
    @State private var seekValue = 0.0
    @State private var isSeeking = false

    var body: some View {
        VStack(spacing: 0) {
            RealityView { content in
                content.add(model.videoEntity)
                model.realityViewDidAttach()
            }
            .frame(minWidth: 760, minHeight: 500)
            .background(.black)

            Divider()
            controls
            Divider()
            diagnostics
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .data]
        ) { result in
            switch result {
            case .success(let url):
                Task { await model.open(url) }
            case .failure(let error):
                assertionFailure(error.localizedDescription)
            }
        }
        .onDisappear {
            Task { await model.close() }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button("Open Video…") { isImporting = true }
                    .keyboardShortcut("o")
                    .disabled(model.isTransitioning)

                Spacer()
                Text(model.selectedURL?.lastPathComponent ?? "No video selected")
                    .lineLimit(1)
                Text(model.status.label)
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 12) {
                Button { model.playPause() } label: {
                    Image(systemName: model.status == .playing ? "pause.fill" : "play.fill")
                }
                .disabled(!model.canControl)

                Button("−10 s") { Task { await model.skip(by: -10) } }
                    .disabled(!model.canControl)

                Text(Self.time(isSeeking ? seekValue : model.currentSeconds))
                    .monospacedDigit()
                Slider(
                    value: Binding(
                        get: { isSeeking ? seekValue : model.currentSeconds },
                        set: { seekValue = $0 }
                    ),
                    in: 0...max(model.durationSeconds, 0.01),
                    onEditingChanged: { editing in
                        isSeeking = editing
                        if !editing { Task { await model.seek(to: seekValue) } }
                    }
                )
                .disabled(!model.canControl)
                Text(Self.time(model.durationSeconds))
                    .monospacedDigit()

                Button("+10 s") { Task { await model.skip(by: 10) } }
                    .disabled(!model.canControl)

                Picker("Rate", selection: Binding(
                    get: { model.playbackRate },
                    set: { model.setRate($0) }
                )) {
                    Text("0.5×").tag(Float(0.5))
                    Text("1×").tag(Float(1))
                    Text("1.5×").tag(Float(1.5))
                    Text("2×").tag(Float(2))
                }
                .frame(width: 100)
                .disabled(!model.canControl)

                Button { model.setMuted(!model.isMuted) } label: {
                    Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .disabled(!model.canControl)
                Slider(
                    value: Binding(
                        get: { Double(model.volume) },
                        set: { model.setVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .frame(width: 90)
                .disabled(!model.canControl)

                Button("Reopen") { Task { await model.reopen() } }
                    .disabled(model.selectedURL == nil || model.isTransitioning)
                Button("Close") { Task { await model.close() } }
                    .disabled(model.selectedURL == nil)
            }
        }
        .padding(12)
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.diagnostics.compactSummary)
            Text(verbatim: "displayedFrame: \(model.displayedFrameAvailable) · displayedPixelFormat: \(model.displayedPixelFormat)")
            Text(verbatim: "audioSampleBuffers: \(model.audioSampleBufferCount) · audioFrames: \(model.audioFrameCount) · audioError: \(model.audioError)")
            if let controlError = model.controlError {
                Text(controlError).foregroundStyle(.red)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var statusColor: Color {
        if case .failed = model.status { return .red }
        return .secondary
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        return String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
