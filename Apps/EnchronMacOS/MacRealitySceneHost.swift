import OSLog
import PlaybackPresentation
import RealityKit
import SwiftUI

private let macEnvironmentSceneLogger = Logger(
    subsystem: "app.enchron",
    category: "MacEnvironmentSceneHost"
)

struct MacEnvironmentSceneHostView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            MacEnvironmentRealityScene()

            EnvironmentCardCarousel(
                activeEnvironment: appModel.environmentContext.environment,
                defaultEffect: appModel.currentEnvironmentEffect,
                onEffectChange: { featured, effect in
                    guard appModel.environmentContext.environment
                            == featured.environment else { return }
                    appModel.setActiveEnvironmentEffect(effect)
                },
                onExpand: { featured, effect in
                    if appModel.environmentContext.environment == featured.environment {
                        try? appModel.deactivateEnvironment()
                    } else {
                        try? appModel.activateEnvironment(
                            featured.environment,
                            effect: effect
                        )
                    }
                }
            )
        }
        .background(.black)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MacEnvironment-SceneHost")
    }
}

private struct MacEnvironmentRealityScene: View {
    @State private var world: Entity?
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        ZStack {
            RealityView { content in
                content.camera = .virtual
                await loadWorldIfNeeded()
                if let world {
                    content.add(world)
                }
            } update: { content in
                content.camera = .virtual
                if let world,
                   content.entities.contains(where: { $0 === world }) == false {
                    content.add(world)
                }
            }
            .realityViewCameraControls(.orbit)

            if isLoading {
                ProgressView("Loading environment…")
            }

            if let loadError {
                ContentUnavailableView(
                    "Environment Unavailable",
                    systemImage: "cube.transparent",
                    description: Text(loadError)
                )
            }
        }
    }

    @MainActor
    private func loadWorldIfNeeded() async {
        guard world == nil, isLoading == false, loadError == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedWorld = try await Entity(named: EnvironmentSceneMapping.worldSceneName)
            _ = try PlaybackSurfaceAnchorResolver.resolve(in: loadedWorld)
            world = loadedWorld
            macEnvironmentSceneLogger.notice("RCP world loaded")
        } catch {
            loadError = error.localizedDescription
            macEnvironmentSceneLogger.error(
                "RCP world load failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
