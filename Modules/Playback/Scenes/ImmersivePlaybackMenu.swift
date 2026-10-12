import DesignSystem
import RealityKit
import SwiftUI

@Observable
final class ImmersivePlaybackMenu {
    static let attachmentID = "immersivePlaybackMenu"
    static let coordinateSpace = "immersivePlaybackControls"

    let presentation = AnchoredMenuPresentation()
    var controlsSize: CGSize = .zero
    var buttonFrame: CGRect = .zero

    var canvasSize: CGSize {
        CGSize(width: controlsSize.width + DesignTokens.Menu.maximumWidth * 2,
               height: controlsSize.height + DesignTokens.Menu.maximumContentHeight * 2)
    }

    func toggle(live: FusedPlayerPanelLive) {
        if presentation.isActive {
            presentation.dismiss()
            return
        }
        presentation.bounds = CGRect(origin: .zero, size: canvasSize)
        presentation.preferredEdge = .above
        let source = buttonFrame.offsetBy(
            dx: (canvasSize.width - controlsSize.width) / 2,
            dy: (canvasSize.height - controlsSize.height) / 2
        )
        live.onReachabilityAction("menu.more")
        presentation.present(key: "playback.more", source: source) {
            ImmersiveMenuCategories(live: live, presentation: self.presentation)
        }
    }

    func position(in controlsBounds: BoundingBox) -> SIMD3<Float> {
        controlsBounds.center
    }
}

extension EnvironmentValues {
    @Entry var immersivePlaybackMenu: ImmersivePlaybackMenu?
}

struct ImmersivePlaybackMenuView: View {
    let menu: ImmersivePlaybackMenu

    var body: some View {
        AnchoredMenuLayer(presentation: menu.presentation)
            .accessibilityIdentifier("PlayerPanel-immersive-more-menu")
    }
}

private enum PlaybackMenuCategory: String, CaseIterable {
    case subtitles, audio, speed, episodes

    var title: String {
        switch self {
        case .subtitles: String(localized: "Subtitles")
        case .audio: String(localized: "Audio Track")
        case .speed: String(localized: "Playback Speed")
        case .episodes: String(localized: "Episodes")
        }
    }

    func items(in live: FusedPlayerPanelLive) -> [DeckMenuItem] {
        switch self {
        case .subtitles: live.subtitleItems
        case .audio: live.audioItems
        case .speed: live.speedItems
        case .episodes: live.episodeItems
        }
    }

    func identifier(for item: DeckMenuItem) -> String {
        let category = switch self {
        case .subtitles: "subtitle"
        case .audio: "audio"
        case .speed: "speed"
        case .episodes: "episode"
        }
        return "PlayerPanel-menu-\(category)-\(item.id)"
    }

    var identifier: String {
        switch self {
        case .subtitles: "PlayerPanel-menu-subtitles"
        case .audio: "PlayerPanel-menu-audio"
        case .speed: "PlayerPanel-menu-speed"
        case .episodes: "PlayerPanel-menu-episodes"
        }
    }
}

private struct ImmersiveMenuCategories: View {
    let live: FusedPlayerPanelLive
    let presentation: AnchoredMenuPresentation

    var body: some View {
        VStack(spacing: 0) {
            ForEach(PlaybackMenuCategory.allCases, id: \.self) { category in
                if !category.items(in: live).isEmpty {
                    AnchoredMenuRow(category.title,
                                    identifier: category.identifier,
                                    isSelected: presentation.selectedSubmenu == category.rawValue) { source in
                        live.onReachabilityAction("menu.\(category.rawValue)")
                        let sizing: AnchoredMenuSizing = category == .episodes
                            ? .grid(itemCount: category.items(in: live).count) : .content
                        presentation.presentSubmenu(key: category.rawValue, source: source, sizing: sizing) {
                            ImmersiveMenuOptions(category: category, live: live, presentation: presentation)
                        }
                    }
                    .disabled(category == .subtitles && !live.subtitlesEnabled)
                }
            }
        }
    }
}

private struct ImmersiveMenuOptions: View {
    let category: PlaybackMenuCategory
    let live: FusedPlayerPanelLive
    let presentation: AnchoredMenuPresentation
    @State private var episodeLayout = 0

    private var items: [DeckMenuItem] { category.items(in: live) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if category == .episodes {
                ViewModeCapsuleControl(selection: $episodeLayout,
                                       accessibilityIdentifier: "PlayerPanel-menu-episodes-layout")
            }
            if category == .episodes, episodeLayout == 0 {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: DesignTokens.Interactive.large), spacing: 0)],
                          spacing: 0) {
                    ForEach(items) { item in
                        AnchoredMenuNumber(item.compactTitle ?? item.title, title: item.title,
                                           identifier: category.identifier(for: item),
                                           isSelected: item.isSelected) {
                            select(item)
                        }
                    }
                }
            } else {
                ForEach(items) { item in
                    MenuSelectionRow(item.title, isSelected: item.isSelected,
                                     identifier: category.identifier(for: item)) {
                        select(item)
                    }
                    .buttonStyle(AnchoredMenuButtonStyle())
                    .accessibilityAddTraits(item.isSelected ? .isSelected : [])
                }
            }
        }
    }

    private func select(_ item: DeckMenuItem) {
        live.onReachabilityAction("menu.item.\(item.id)")
        presentation.dismiss()
        item.action()
    }
}
