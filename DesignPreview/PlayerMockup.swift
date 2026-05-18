import SwiftUI

// MARK: - Player Mockup
// Simulates the player layout: video + scenes + controls + timeline + menu

#Preview(windowStyle: .automatic) {
    PlayerMockupView()
}

struct PlayerMockupView: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: DesignTokens.Spacing.md) {
                PlayerVideoPlaceholder()
                PlayerSceneSelector()
                Spacer()
                PlayerNowPlaying()
                PlayerTimeline()
                PlayerControlBar()
            }
            .padding(DesignTokens.Spacing.lg)

            PlayerMenuOverlay()
                .padding(.leading, DesignTokens.Spacing.xxl)
                .padding(.bottom, 200)
        }
        .navigationTitle("Player")
    }
}

// MARK: - Video placeholder

private struct PlayerVideoPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous)
            .fill(Color.black.opacity(0.3))
            .frame(height: 200)
            .overlay {
                VStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "play.fill")
                        .font(DesignTokens.SymbolSize.hero)
                        .foregroundStyle(.tertiary)
                    Text("Video Area")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.tertiary)
                }
            }
    }
}

// MARK: - Scene selector

private struct PlayerSceneSelector: View {
    private let scenes: [(String, String)] = [
        ("mountain.2", "Cinema"),
        ("moon.stars", "Night Sky"),
        ("water.waves", "Ocean"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("IMMERSIVE SCENES")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(scenes, id: \.1) { icon, name in
                    SceneCardMedium(icon: icon, title: name, isSelected: name == "Cinema")
                }
            }
        }
    }
}

// MARK: - Now playing

private struct PlayerNowPlaying: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Now Playing: Interstellar")
                    .font(DesignTokens.Typography.headline)
                Text("02:31:45 / 02:49:00")
                    .font(DesignTokens.Typography.monospacedDetail)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text("Auto-play").font(.body).foregroundStyle(.secondary)
                MockToggle(isOn: true)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .enchronGlassPanel()
    }
}

// MARK: - Timeline

struct PlayerTimeline: View {
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignTokens.Surface.elevated)
                    Capsule().fill(Color(red: 0.224, green: 0.773, blue: 0.733))
                        .frame(width: geo.size.width * 0.6)
                }
            }
            .frame(height: 6)
            .padding(.bottom, DesignTokens.Spacing.xs)

            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(0..<12, id: \.self) { i in
                    TimelineTick(index: i)
                }
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.224, green: 0.773, blue: 0.733))
                    .frame(width: 2, height: 24)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .enchronGlassToolbar()
    }
}

private struct TimelineTick: View {
    let index: Int
    var body: some View {
        let isMajor = index % 4 == 0
        VStack(spacing: 2) {
            Rectangle()
                .fill(.white.opacity(isMajor ? 0.5 : 0.2))
                .frame(width: DesignTokens.Stroke.regular, height: isMajor ? 16 : 10)
            if isMajor {
                Text("\(index * 5)s")
                    .font(DesignTokens.Typography.monospacedDetail)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Control bar

struct PlayerControlBar: View {
    var body: some View {
        HStack(spacing: DesignTokens.Interactive.buttonSpacing) {
            Image(systemName: "backward.fill")
                .font(DesignTokens.SymbolSize.control)
                .frame(width: DesignTokens.Interactive.large,
                       height: DesignTokens.Interactive.large)

            Image(systemName: "play.fill")
                .font(DesignTokens.SymbolSize.action)
                .frame(width: DesignTokens.Interactive.xl,
                       height: DesignTokens.Interactive.xl)

            Image(systemName: "forward.fill")
                .font(DesignTokens.SymbolSize.control)
                .frame(width: DesignTokens.Interactive.large,
                       height: DesignTokens.Interactive.large)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .enchronGlassControl()
    }
}

// MARK: - Menu overlay

private struct PlayerMenuOverlay: View {
    @State private var expandedItem: String?
    private let menuItems = ["Audio Track", "Subtitle", "Speed"]
    private let submenuData: [String: [String]] = [
        "Audio Track": ["English 5.1", "Japanese 2.0", "Commentary"],
        "Subtitle": ["English (CC)", "中文简体", "Off"],
        "Speed": ["0.5×", "1.0×", "1.5×", "2.0×"],
    ]

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
            VStack(spacing: DesignTokens.Spacing.xxs) {
                ForEach(menuItems, id: \.self) { item in
                    Button {
                        withAnimation(DesignTokens.AnimationToken.menuPopup) {
                            expandedItem = expandedItem == item ? nil : item
                        }
                    } label: {
                        MenuItemRow(title: item, isExpanded: expandedItem == item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignTokens.Menu.glassPadding)
            .frame(width: DesignTokens.Menu.panelWidth)
            .enchronGlassMenu()

            if let selected = expandedItem, let options = submenuData[selected] {
                VStack(spacing: DesignTokens.Spacing.xxs) {
                    ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                        SubMenuItemRow(title: option, isChecked: idx == 0)
                    }
                }
                .padding(DesignTokens.Menu.glassPadding)
                .frame(width: DesignTokens.Menu.submenuWidth)
                .enchronGlassMenu()
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
    }
}
