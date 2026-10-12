import RealityKit
import SwiftUI

struct PlaybackSurfaceGestureInput: ViewModifier {
    @Environment(PlaybackSessionModel.self) private var session
    @Environment(PlaybackRuntime.self) private var runtime
    @Environment(\.scenePhase) private var scenePhase

    let acceptsTarget: @MainActor (Entity) -> Bool

    @GestureState private var contactIsActive = false
    @State private var owner = UUID()
    @State private var contactID: UUID?
    @State private var cancellationTask: Task<Void, Never>?
    @State private var hasRecordedTranslation = false
    @State private var hasRecordedNonzeroTranslation = false

    private var controller: PlaybackSurfaceGestureController {
        runtime.surfaceGestureController(session: session)
    }

    private var cancellationContactID: UUID? {
        contactIsActive ? nil : contactID
    }

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(surfaceGesture)
            .onChange(of: cancellationContactID) { _, contactID in
                cancellationTask?.cancel()
                guard let contactID else { return }
                cancellationTask = Task { @MainActor in
                    await Task.yield()
                    guard Task.isCancelled == false, self.contactID == contactID else { return }
                    cancelContact()
                    session.recordSurfaceInputProbe("surfaceGesture input=cancel")
                }
            }
            .onChange(of: session.showControls) {
                controller.synchronize()
            }
            .onChange(of: session.playbackShortcutsEnabled) {
                controller.synchronize()
            }
            .onChange(of: session.playbackPresentation) {
                cancelContact()
            }
            .onChange(of: session.presentationTransition?.id) {
                cancelContact()
            }
            .onChange(of: runtime.activeTechnicalSessionID) {
                cancelContact()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    cancelContact()
                }
            }
            .onDisappear {
                cancelContact()
            }
    }

    private var surfaceGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToAnyEntity()
            .updating($contactIsActive) { value, active, _ in
                active = acceptsTarget(value.entity)
            }
            .onChanged { value in
                guard acceptsTarget(value.entity) else { return }
                if contactID == nil {
                    guard controller.begin(owner: owner) else { return }
                    contactID = UUID()
                    hasRecordedTranslation = false
                    hasRecordedNonzeroTranslation = false
                    session.recordSurfaceInputProbe(
                        "surfaceGesture input=begin entity=\(value.entity.name)"
                    )
                }
                recordTranslation(value, stage: "changed")
                controller.update(
                    horizontalTranslation: Double(value.translation.width),
                    verticalTranslation: Double(value.translation.height),
                    owner: owner
                )
            }
            .onEnded { value in
                guard contactID != nil else { return }
                contactID = nil
                cancellationTask?.cancel()
                recordTranslation(value, stage: "ended", force: true)
                controller.update(
                    horizontalTranslation: Double(value.translation.width),
                    verticalTranslation: Double(value.translation.height),
                    owner: owner
                )
                controller.end(owner: owner)
                session.recordSurfaceInputProbe("surfaceGesture input=end")
            }
    }

    private func recordTranslation(
        _ value: EntityTargetValue<DragGesture.Value>,
        stage: String,
        force: Bool = false
    ) {
        let translation2D = value.translation
        let translation3D = value.translation3D
        let nonzero = translation2D != .zero
            || translation3D.x != 0 || translation3D.y != 0 || translation3D.z != 0
        guard force || hasRecordedTranslation == false
                || (nonzero && hasRecordedNonzeroTranslation == false) else { return }
        hasRecordedTranslation = true
        if nonzero { hasRecordedNonzeroTranslation = true }
        let sceneTranslation = value.convert(translation3D, from: .local, to: .scene)
        session.recordSurfaceInputProbe(
            "surfaceGesture input=translation stage=\(stage) entity=\(value.entity.name)"
                + " phase=\(controller.phase.rawValue)"
                + " translation2D=\(translation2D.width),\(translation2D.height)"
                + " translation3D=\(translation3D.x),\(translation3D.y),\(translation3D.z)"
                + " sceneTranslation=\(sceneTranslation.x),\(sceneTranslation.y),\(sceneTranslation.z)",
            retention: .evidence
        )
    }

    private func cancelContact() {
        contactID = nil
        cancellationTask?.cancel()
        cancellationTask = nil
        controller.cancel(owner: owner)
    }
}
