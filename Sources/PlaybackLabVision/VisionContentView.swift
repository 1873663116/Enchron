import PlaybackCore
import SwiftUI
import UniformTypeIdentifiers

struct VisionContentView: View {
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow
  @Environment(\.openImmersiveSpace) private var openImmersiveSpace
  @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
  @Bindable var model: VisionPlaybackModel
  @State private var isImporting = false
  @State private var seekValue = 0.0
  @State private var isSeeking = false
  @State private var showsPlaybackState = false
  @State private var regressionStatusText: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        if let regressionStatusText {
          GroupBox("真机回归测试") {
            Text(regressionStatusText)
              .font(.body.monospaced())
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
              .padding(.vertical, 6)
          }
        }
        playbackControls
        Divider()
        presentationControls
        if let error = model.presentationTransitionError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
        if showsPlaybackState {
          Text(playbackStateText)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
      .padding(28)
    }
    .frame(width: 760, height: 720)
    .fileImporter(
      isPresented: $isImporting,
      allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .data],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      Task { await model.openImportedVideo(url) }
    }
    .task {
      guard CommandLine.arguments.contains("--presentation-probe") else { return }
      await VisionRegressionRunner(
        model: model,
        actions: presentationActions,
        onProgress: { regressionStatusText = $0 }
      ).runAndExit()
    }
  }

  private var playbackControls: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Playback").font(.title2.bold())

      if model.selectedURL != nil {
        HStack(spacing: 12) {
          Text(time(model.currentSeconds)).monospacedDigit()
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
          .disabled(!model.canSeek)
          Text(time(model.durationSeconds)).monospacedDigit()
        }
      }

      HStack(spacing: 14) {
        Button {
          isImporting = true
        } label: {
          Label("Choose Video", systemImage: "folder")
        }
        .disabled(model.isMediaTransitioning)

        Picker("Route", selection: routeBinding) {
          ForEach(PlaybackRoute.allCases) { route in
            Text(route.label).tag(route)
          }
        }
        .pickerStyle(.segmented)
        .disabled(model.isMediaTransitioning)

        Button {
          showsPlaybackState.toggle()
        } label: {
          Label("State", systemImage: "waveform.path.ecg")
        }
      }

      HStack(spacing: 14) {
        Button { model.play() } label: {
          Label("Play", systemImage: "play.fill")
        }
        .disabled(!model.canPlay)

        Button { model.pause() } label: {
          Label("Pause", systemImage: "pause.fill")
        }
        .disabled(!model.canPause)

        Picker(
          "Speed",
          selection: Binding(get: { model.playbackRate }, set: { model.setRate($0) })
        ) {
          Text("0.5×").tag(Float(0.5))
          Text("1×").tag(Float(1))
          Text("1.5×").tag(Float(1.5))
          Text("2×").tag(Float(2))
        }
        .frame(width: 120)
        .disabled(!model.canAdjustPlayback)

        if let fallbackAudioStreamIndex = model.audioTracks.first?.streamIndex {
          Picker(
            "Audio",
            selection: Binding(
              get: { model.selectedAudioStreamIndex ?? fallbackAudioStreamIndex },
              set: { model.selectAudioTrack($0) }
            )
          ) {
            ForEach(model.audioTracks) { track in
              Text(track.label).tag(track.streamIndex)
            }
          }
          .frame(width: 180)
          .disabled(!model.canAdjustPlayback)
        }

        Button {
          model.setMuted(!model.isMuted)
        } label: {
          Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        }
        .disabled(!model.canAdjustPlayback)

        Slider(
          value: Binding(get: { Double(model.volume) }, set: { model.setVolume(Float($0)) }),
          in: 0...1
        )
        .frame(width: 110)
        .disabled(!model.canAdjustPlayback)
      }

      if model.selectedURL != nil {
        HStack(spacing: 14) {
          VStack(alignment: .leading, spacing: 2) {
            Text(model.selectedURL?.lastPathComponent ?? "")
              .lineLimit(1)
            Text(model.diagnostics.compactSummary)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer()
          Button("Reopen") { Task { await model.reopen() } }
            .disabled(model.isMediaTransitioning || model.isPresentationTransitioning)
          Button(role: .destructive) {
            Task { await model.closeMedia(actions: presentationActions) }
          } label: {
            Label("Close", systemImage: "xmark")
          }
        }
      }

      if let controlError = model.controlError {
        Text(controlError)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
  }

  private var presentationControls: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Presentation").font(.title2.bold())
          Text(model.presentedProductShape?.label ?? "Not Presented")
            .foregroundStyle(.secondary)
        }
        Spacer()
        if model.presentation.state.isTransitioning {
          ProgressView().controlSize(.small)
          Text(model.presentation.state.phase)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
      }

      HStack(spacing: 12) {
        if !model.presentation.isWindowOpen,
          model.presentationFacts.placement == .window
        {
          presentationButton("Open Playback Window", command: .openPlaybackWindow)
        }

        if let sceneCommand = model.presentationFacts.sceneLifecycleCommand {
          presentationButton(
            sceneCommand == .openScene ? "Open Scene" : "Close Scene",
            command: sceneCommand
          )
        }

        if model.presentedProductShape != nil {
          ForEach(Array(model.presentationFacts.primaryPresentationCommands.enumerated()), id: \.offset) {
            _, command in
            presentationButton(label(for: command), command: command)
          }
        }
      }

      Text(
        "Scene: \(model.presentationFacts.sceneLifecycle.stateName) · "
          + "\(model.presentationFacts.sceneContent?.rawValue ?? "none")"
      )
      .font(.caption.monospaced())
      .foregroundStyle(.secondary)

      DisclosureGroup("Advanced") {
        VStack(alignment: .leading, spacing: 12) {
          Picker(
            "Projection",
            selection: Binding(
              get: { model.presentationFacts.projection },
              set: { projection in
                Task {
                  await model.performPresentationCommand(
                    .setProjection(projection),
                    actions: presentationActions
                  )
                }
              }
            )
          ) {
            Text("Flat").tag(VisionProjection.flat)
            Text("Panoramic 360°").tag(VisionProjection.sourcePanoramic)
              .disabled(!model.contentSupportsPanorama)
          }
          .disabled(!model.canIssuePresentationCommand)

          Picker(
            "Stereo",
            selection: Binding(
              get: { model.presentationFacts.stereoLayout },
              set: { layout in
                Task {
                  await model.performPresentationCommand(
                    .setStereo(layout),
                    actions: presentationActions
                  )
                }
              }
            )
          ) {
            Text("Mono").tag(VisionStereoLayout.mono)
            Text("Side by Side").tag(VisionStereoLayout.sideBySide)
            Text("Over / Under").tag(VisionStereoLayout.overUnder)
          }
          .disabled(!model.canIssuePresentationCommand)
        }
        .padding(.top, 10)
      }
    }
  }

  private func presentationButton(
    _ label: String,
    command: PresentationCommand
  ) -> some View {
    Button(label) {
      Task {
        await model.performPresentationCommand(command, actions: presentationActions)
      }
    }
    .disabled(isPresentationCommandDisabled(command))
  }

  private func isPresentationCommandDisabled(_ command: PresentationCommand) -> Bool {
    if model.isMediaTransitioning || model.isPresentationTransitioning { return true }
    switch command {
    case .openPlaybackWindow, .closePlaybackWindow, .openScene, .closeScene:
      return false
    case .showWindow, .dock, .showPanorama, .setProjection, .setStereo:
      return !model.canIssuePresentationCommand
    }
  }

  private func label(for command: PresentationCommand) -> String {
    switch command {
    case .dock: "Dock"
    case .showPanorama: "Panorama"
    case .showWindow:
      model.presentedProductShape == .panorama ? "Portal" : "Window"
    case .openPlaybackWindow: "Open Playback Window"
    case .closePlaybackWindow: "Close Playback Window"
    case .openScene: "Open Scene"
    case .closeScene: "Close Scene"
    case .setProjection: "Projection"
    case .setStereo: "Stereo"
    }
  }

  private var playbackStateText: String {
    let state = model.presentationStateSnapshot()
    return [
      "shape=\(state["productShape"] ?? "unknown") projection=\(state["projection"] ?? "unknown")",
      "placement=\(state["placement"] ?? "unknown") stereo=\(state["stereoLayout"] ?? "unknown")",
      "scene=\(state["sceneLifecycle"] ?? "unknown")/\(state["sceneContent"] ?? "none") requested=\(state["customSceneRequestedOpen"] ?? false)",
      "immersive=\(state["desiredImmersiveViewingMode"] ?? "unknown")/\(state["actualImmersiveViewingMode"] ?? "none")",
      "viewing=\(state["desiredViewingMode"] ?? "unknown")/\(state["actualViewingMode"] ?? "none")",
      "rendererMatches=\(state["rendererMatchesSession"] ?? false) session=\(state["mediaSessionID"] ?? "none")",
      "audio=\(model.selectedAudioStreamIndex.map(String.init) ?? "none") time=\(time(model.currentSeconds)) status=\(model.status.label)",
      "transitioning=\(state["transitioning"] ?? false) error=\(state["transitionError"] ?? "none")",
    ].joined(separator: "\n")
  }

  private var presentationActions: VisionPresentationActions {
    VisionPresentationActions(
      openWindow: { id, request in openWindow(id: id, value: request) },
      dismissWindow: { id, request in dismissWindow(id: id, value: request) },
      openImmersiveSpace: { id, request in
        switch await openImmersiveSpace(id: id, value: request) {
        case .opened:
          return .opened
        case .userCancelled:
          return .userCancelled
        case .error:
          return .failed("openImmersiveSpace.error")
        @unknown default:
          return .failed("openImmersiveSpace.unknownResult")
        }
      },
      dismissImmersiveSpace: { await dismissImmersiveSpace() }
    )
  }

  private var routeBinding: Binding<PlaybackRoute> {
    Binding(
      get: { model.selectedRoute },
      set: { route in Task { await model.selectRoute(route) } }
    )
  }

  private func time(_ seconds: Double) -> String {
    guard seconds.isFinite && seconds >= 0 else { return "00:00" }
    let total = Int(seconds.rounded(.down))
    return String(format: "%02d:%02d", total / 60, total % 60)
  }
}
