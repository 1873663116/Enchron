import SwiftUI

public struct SceneSelectorView: View {
    @Environment(AppModel.self) var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    let columns = [
        GridItem(.adaptive(minimum: 200))
    ]

    public init() {}

    public var body: some View {
        VStack {
            ToggleImmersiveSpaceButton()
                .padding(.vertical, 24)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 32) {
                    ForEach(SpatialSceneDomain.CinemaEnvironment.allCases, id: \.self) { environment in
                        let isSelected = appModel.currentCinemaEnvironment == environment
                        Button {
                            Task {
                                await appModel.switchEnvironment(to: environment)
                                if appModel.immersiveSpaceState == .closed {
                                    appModel.immersiveSpaceState = .inTransition
                                    switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                                    case .opened:
                                        break
                                    case .userCancelled, .error:
                                        appModel.immersiveSpaceState = .closed
                                    @unknown default:
                                        appModel.immersiveSpaceState = .closed
                                    }
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                                    .fill(.clear)
                                    .aspectRatio(16/9, contentMode: .fill)
                                    .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
                                    .overlay {
                                        ZStack {
                                            if isSelected {
                                                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                                                    .stroke(Color.accentColor, lineWidth: 3)
                                                    .blur(radius: 2)
                                            }

                                            Image(systemName: iconName(for: environment))
                                                .font(.system(size: 44))
                                                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                                        }
                                    }
                                    .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
                                    .hoverEffect()

                                Text(environment.displayName)
                                    .font(.headline)
                                    .padding(.leading, 8)
                                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(isSelected ? 1.02 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: appModel.currentCinemaEnvironment)
                    }
                }
                .padding(32)
            }

            Text(appModel.currentCinemaEnvironment.displayName)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
        .navigationTitle("Scenes")
    }

    private func iconName(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> String {
        switch environment {
        case .darkTheatre: return "moon.fill"
        case .starryNight: return "star.fill"
        case .sunsetNature: return "sun.horizon.fill"
        }
    }
}
