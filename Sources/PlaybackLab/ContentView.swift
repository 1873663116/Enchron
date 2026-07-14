import RealityKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = PlaybackModel()
    @State private var isImporting = false
    @State private var showsDiagnostics = false
    @State private var seekValue = 0.0
    @State private var isSeeking = false

    var body: some View {
        VStack(spacing: 0) {
            realityVideo
            .frame(minWidth: 720, minHeight: 480)
            .background(.black)

            Divider()

            playbackControls

            Divider()

            HStack(spacing: 12) {
                Button("Open Video…") {
                    isImporting = true
                }
                .keyboardShortcut("o")
                .disabled(model.isMediaTransitioning)

                Picker("Route", selection: routeBinding) {
                    ForEach(PlaybackRoute.allCases) { route in
                        Text(route.label).tag(route)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 430)
                .disabled(model.isMediaTransitioning)

                Button {
                    showsDiagnostics.toggle()
                } label: {
                    Label("Diagnostics", systemImage: "waveform.path.ecg")
                }

                Button("Repro 00:07.508") {
                    Task { await model.openKnownOverexposurePoint() }
                }
                .disabled(model.isMediaTransitioning)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(model.selectedURL?.lastPathComponent ?? "No video selected")
                        .lineLimit(1)
                    Text(model.status.label)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    if let controlError = model.controlError {
                        Text(controlError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            }
            .padding(12)

            if model.selectedURL != nil {
                Divider()
                diagnosticsBar
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .data]
        ) { result in
            switch result {
            case .success(let url):
                Task { await model.open(url) }
            case .failure(let error):
                model.reportFileImportFailure(error)
            }
        }
        .task {
            await model.openDefaultVideo()
        }
        .onDisappear {
            model.close()
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 12) {
            Button { model.status == .playing ? model.pause() : model.play() } label: {
                Image(systemName: model.status == .playing ? "pause.fill" : "play.fill")
            }
            .disabled(model.status == .playing ? !model.canPause : !model.canPlay)

            Text(time(model.currentSeconds))
                .monospacedDigit()
            Slider(
                value: Binding(get: { isSeeking ? seekValue : model.currentSeconds }, set: { seekValue = $0 }),
                in: 0...max(model.durationSeconds, 0.01),
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing { Task { await model.seek(to: seekValue) } }
                }
            )
            .disabled(!model.canSeek)
            Text(time(model.durationSeconds))
                .monospacedDigit()

            Picker("Speed", selection: Binding(get: { model.playbackRate }, set: { model.setRate($0) })) {
                Text("0.5×").tag(Float(0.5))
                Text("1×").tag(Float(1))
                Text("1.5×").tag(Float(1.5))
                Text("2×").tag(Float(2))
            }
            .frame(width: 100)
            .disabled(!model.canAdjustPlayback)

            if let fallbackAudioStreamIndex = model.audioTracks.first?.streamIndex {
                Picker("Audio", selection: Binding(
                    get: { model.selectedAudioStreamIndex ?? fallbackAudioStreamIndex },
                    set: { model.selectAudioTrack($0) }
                )) {
                    ForEach(model.audioTracks) { track in Text(track.label).tag(track.streamIndex) }
                }
                .frame(width: 190)
                .disabled(!model.canAdjustPlayback)
            }

            Button { model.setMuted(!model.isMuted) } label: {
                Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .disabled(!model.canAdjustPlayback)
            Slider(value: Binding(get: { Double(model.volume) }, set: { model.setVolume(Float($0)) }), in: 0...1)
                .frame(width: 100)
                .disabled(!model.canAdjustPlayback)

            Button("Reopen") { Task { await model.reopen() } }
                .disabled(model.selectedURL == nil || model.isMediaTransitioning)

            Button("Close") { Task { await model.closeAndWait() } }
                .disabled(!model.canClose)
        }
        .padding(12)
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00" }
        return String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private var realityVideo: some View {
        RealityView { content in
            content.add(model.videoEntity)
            model.realityViewDidAttachEntity()
        }
    }

    private var routeBinding: Binding<PlaybackRoute> {
        Binding(
            get: { model.selectedRoute },
            set: { route in Task { await model.selectRoute(route) } }
        )
    }

    private var diagnosticsBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.diagnostics.compactSummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy Snapshot") {
                    model.copyDiagnostics()
                }
            }

            if showsDiagnostics {
                Text(model.diagnostics.snapshotText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var statusColor: Color {
        if case .failed = model.status { return .red }
        return .secondary
    }
}
