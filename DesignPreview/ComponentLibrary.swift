import SwiftUI

// MARK: - Bare button style (no built-in hover, no chrome)

/// Custom ButtonStyle that disables the system's default hover effect.
/// Unlike `.plain`, a custom ButtonStyle does not add automatic hover highlight.
private struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

// MARK: - Component Library
// Every component isolated with labels showing token/variant info.

struct ComponentLibraryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                PlayerSection()
                CircleButtonsSection()
                ToggleSection()
                LoadingSection()
                CardsSection()
                RowsSection()
                ContainersSection()
                InteractiveMenuSection()
                SmallElementsSection()
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .navigationTitle("Components")
    }
}

// MARK: - Circle Buttons (interactive: tap to select/deselect)

private struct CircleButtonsSection: View {
    @State private var selected: String?
    @State private var viewMode = 0
    @State private var sortKey: SortKey = .name
    @State private var sortOrder: SortOrder = .ascending
    @State private var searchText = ""
    @State private var isSearchSelected = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("CIRCLE BUTTONS")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            HStack(spacing: DesignTokens.Spacing.xl) {
                labeledComponent("Back") {
                    interactiveCircle("chevron.left", id: "back")
                }
                labeledComponent("Forward") {
                    interactiveCircle("chevron.right", id: "forward")
                }
                labeledComponent("Sort") {
                    sortMenuButton
                }
                labeledComponent("Source Menu") {
                    sourceMenuButton
                }

                labeledComponent("Nav Back/Forward") {
                    NavBackForwardCapsuleControl(
                        iconColor: .white,
                        accessibilityIdentifier: "DesignPreview-ComponentLibrary-control-navBackForward"
                    )
                }

                labeledComponent("View Mode (tap to switch)") {
                    ViewModeCapsuleControl(
                        selection: $viewMode,
                        iconColor: .white,
                        accessibilityIdentifier: "DesignPreview-ComponentLibrary-control-viewMode"
                    )
                }
                labeledComponent("Search") {
                    searchInputCapsule
                }
            }

            Text("44pt glass circle · hover + selected · tap to toggle")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func interactiveCircle(_ icon: String, id: String) -> some View {
        let isSelected = selected == id
        Button {
            withAnimation(DesignTokens.AnimationToken.selection) {
                selected = isSelected ? nil : id
            }
        } label: {
            Image(systemName: icon)
                .font(DesignTokens.SymbolSize.control)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: DesignTokens.Interactive.regular,
                       height: DesignTokens.Interactive.regular)
        }
        .buttonStyle(.plain)
        .clipShape(Circle())
        .glassBackgroundEffect(in: Circle())
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.automatic)
        .padding((DesignTokens.Interactive.large - DesignTokens.Interactive.regular) / 2)
        .contentShape(Circle())
        .enchronPressFeedback(.icon)
    }

    @ViewBuilder
    private var sortMenuButton: some View {
        Menu {
            Section("Sort By") {
                Button {
                    sortKey = .name
                } label: {
                    Label("Name", systemImage: sortKey == .name ? "checkmark" : "")
                }
                Button {
                    sortKey = .modifiedDate
                } label: {
                    Label("Date Modified", systemImage: sortKey == .modifiedDate ? "checkmark" : "")
                }
                Button {
                    sortKey = .size
                } label: {
                    Label("Size", systemImage: sortKey == .size ? "checkmark" : "")
                }
            }

            Menu("Order") {
                Button {
                    sortOrder = .ascending
                } label: {
                    Label("Ascending", systemImage: sortOrder == .ascending ? "checkmark" : "")
                }
                Button {
                    sortOrder = .descending
                } label: {
                    Label("Descending", systemImage: sortOrder == .descending ? "checkmark" : "")
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(DesignTokens.SymbolSize.control)
                .foregroundStyle(.secondary)
                .frame(width: DesignTokens.Interactive.regular,
                       height: DesignTokens.Interactive.regular)
                .clipShape(Circle())
                .glassBackgroundEffect(in: Circle())
                .contentShape(.hoverEffect, Circle())
                .hoverEffect(.automatic)
                .contentShape(Circle())
                .enchronPressFeedback(.icon)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DesignPreview-ComponentLibrary-menu-sort")
        .accessibilityLabel("Sort Menu")
    }

    private var searchInputCapsule: some View {
        let isActive = isSearchSelected || isSearchFieldFocused

        return HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.tertiary)

            TextField("搜索", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.secondary)
                .focused($isSearchFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .hoverEffectDisabled()
                .allowsHitTesting(false)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(width: 280, height: DesignTokens.Interactive.regular)
        .clipShape(Capsule())
        .glassBackgroundEffect(in: Capsule())
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.automatic)
        .contentShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    DesignTokens.Surface.focusBorder.opacity(isActive ? 1 : 0),
                    lineWidth: DesignTokens.Stroke.bold
                )
                .animation(DesignTokens.AnimationToken.selection, value: isActive)
        }
        .onTapGesture {
            withAnimation(DesignTokens.AnimationToken.selection) {
                isSearchSelected = true
                isSearchFieldFocused = true
            }
        }
        .onChange(of: isSearchFieldFocused) { _, isFocused in
            guard !isFocused else { return }
            withAnimation(DesignTokens.AnimationToken.selection) {
                isSearchSelected = false
            }
        }
        .accessibilityIdentifier("DesignPreview-ComponentLibrary-input-search")
        .accessibilityLabel("Search")
    }

    private var sourceMenuButton: some View {
        Menu {
            Section("Local") {
                Button("Choose Folder...") {}
                Button("Import Video...") {}
                Button("Photo Library...") {}
                Button("Use App Documents") {}
            }
            Section("Remote") {
                Button("Add WebDAV Server...") {}
                Button("Add SMB Server...") {}
                Menu("Reconnect") {
                    Button("SMB://NAS") {}
                    Button("WebDAV://Drive") {}
                }
            }
            Button("Disconnect", role: .destructive) {}
        } label: {
            Image(systemName: "ellipsis")
                .font(DesignTokens.SymbolSize.control)
                .foregroundStyle(.secondary)
                .frame(width: DesignTokens.Interactive.regular,
                       height: DesignTokens.Interactive.regular)
                .clipShape(Circle())
                .glassBackgroundEffect(in: Circle())
                .contentShape(.hoverEffect, Circle())
                .hoverEffect(.automatic)
                .contentShape(Circle())
                .enchronPressFeedback(.icon)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DesignPreview-ComponentLibrary-menu-source")
        .accessibilityLabel("Source Menu")
    }

    private enum SortKey {
        case name
        case modifiedDate
        case size
    }

    private enum SortOrder {
        case ascending
        case descending
    }
}


// MARK: - Loading spinner

private struct LoadingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("LOADING")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xl) {
                labeledComponent("Small (36pt)") {
                    LoadingSpinner(size: 36)
                }
                labeledComponent("Default (56pt)") {
                    LoadingSpinner()
                }
                labeledComponent("Large (80pt)") {
                    LoadingSpinner(size: 80)
                }
            }

            Text("Glass circle · #39C5BB glow · arc stretch")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Toggle (interactive, glass material)

private struct ToggleSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("TOGGLE")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            HStack(spacing: DesignTokens.Spacing.xl) {
                labeledComponent("Tap to toggle") {
                    MockToggle(isOn: true)
                }
            }

            Text("50×30pt · glass material · tap to switch")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Cards

private struct CardsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("CARDS")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            HStack(alignment: .top, spacing: DesignTokens.Card.gridSpacing) {
                labeledComponent("VideoCardLarge\ncard(32) + lift") {
                    VideoCardLarge(title: "Interstellar", fileSize: "8.2 GB",
                                   duration: "2:49:00", badges: ["HDR10+"])
                }
                labeledComponent("SceneCardMedium\ncard(32) + lift") {
                    SceneCardMedium(icon: "mountain.2", title: "Cinema", isSelected: false)
                }
                labeledComponent("FolderCard\ncard(32) + lift") {
                    FolderCard(title: "Movies", count: 24)
                }
            }
        }
    }
}

// MARK: - Rows

private struct RowsSection: View {
    @State private var selectedAudioTrack = "English 5.1"
    @State private var selectedCaptions = "Off"

    private let audioTracks = ["English 5.1", "Japanese 2.0", "Commentary"]
    private let captionTracks = ["Off", "English (CC)", "中文简体"]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("ROWS / LIST ITEMS")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                VStack(spacing: DesignTokens.Spacing.xxs) {
                    FileListRow(icon: "folder", title: "Movies", metadata: "24 items")
                    FileListRow(icon: "film", title: "Blade Runner 2049", metadata: "4K · 5.3 GB")
                }
                .frame(maxWidth: 600)

                VStack(spacing: DesignTokens.Spacing.xxs) {
                    NativeSelectionMenuRow(
                        title: "Audio Track",
                        selection: $selectedAudioTrack,
                        options: audioTracks
                    )
                    NativeSelectionMenuRow(
                        title: "Captions",
                        selection: $selectedCaptions,
                        options: captionTracks
                    )
                }
                .frame(width: DesignTokens.Menu.panelWidth)
            }

            Text("element(24) + highlight hover · minHeight 60pt")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

private struct NativeSelectionMenuRow: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Label(option, systemImage: option == selection ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(title)
                        .font(.body)
                    Text(selection)
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: DesignTokens.Spacing.sm)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(minHeight: DesignTokens.Interactive.rowHeight)
            .enchronGlassMenuItem()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DesignPreview-ComponentLibrary-menu-\(title)")
        .accessibilityLabel(title)
    }
}

// MARK: - Containers

private struct ContainersSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("CONTAINERS")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            HStack(alignment: .top, spacing: DesignTokens.Spacing.xl) {
                // Menu container
                labeledComponent("MenuContainer\ncard(32) · 8pt padding → element(24)") {
                    VStack(spacing: DesignTokens.Spacing.xxs) {
                        MenuItemRow(title: "Option A", isExpanded: false)
                        MenuItemRow(title: "Option B", isExpanded: false)
                        MenuItemRow(title: "Option C", isExpanded: false)
                    }
                    .padding(DesignTokens.Menu.glassPadding)
                    .frame(width: DesignTokens.Menu.panelWidth)
                    .enchronGlassMenu()
                }

                // Source menu (with disconnect)
                labeledComponent("SourceMenu\n(red destructive action)") {
                    VStack(spacing: DesignTokens.Spacing.xxs) {
                        MenuItemRow(title: "Connect New Source", isExpanded: false)
                        HStack {
                            Text("Disconnect").font(.body).foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .frame(minHeight: DesignTokens.Interactive.rowHeight)
                        .enchronGlassMenuItem()
                    }
                    .padding(DesignTokens.Menu.glassPadding)
                    .frame(width: DesignTokens.Menu.panelWidth)
                    .enchronGlassMenu()
                }

                // Large panel
                labeledComponent("LargePanel\npanel(40) regularMaterial") {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        Text("Settings Panel").font(DesignTokens.Typography.headline)
                        Text("Content with regularMaterial background.")
                            .font(.body).foregroundStyle(.secondary)
                    }
                    .padding(DesignTokens.Spacing.lg)
                    .frame(width: 280)
                    .enchronGlassPanel()
                }
            }
        }
    }
}

// MARK: - Interactive Menu + Submenu

private struct InteractiveMenuSection: View {
    @State private var expandedItem: String?
    private let menuItems = ["Audio Track", "Subtitle", "Speed"]
    private let submenuData: [String: [String]] = [
        "Audio Track": ["English 5.1", "Japanese 2.0", "Commentary"],
        "Subtitle": ["English (CC)", "中文简体", "Off"],
        "Speed": ["0.5×", "1.0×", "1.5×", "2.0×"],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("MENU + SUBMENU")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

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

            Text("点击条目展开子菜单 · menuPopup 动效 · glass material")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Small elements

private struct SmallElementsSection: View {
    @State private var selectedFilter = "All"
    private let filters = ["All", "Movies", "TV Shows", "Concerts"]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("SMALL ELEMENTS")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            HStack(spacing: DesignTokens.Spacing.xl) {
                labeledComponent("Badges · Capsule ultraThin") {
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        badgeItem("HDR10+")
                        badgeItem("MV-HEVC")
                        badgeItem("Atmos")
                    }
                }

                labeledComponent("FilterPills · 点击切换") {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(filters, id: \.self) { filter in
                            Button {
                                withAnimation(DesignTokens.AnimationToken.selection) {
                                    selectedFilter = filter
                                }
                            } label: {
                                Text(filter)
                                    .font(.body)
                                    .foregroundStyle(selectedFilter == filter ? .primary : .secondary)
                                    .padding(.horizontal, DesignTokens.Spacing.md)
                                    .padding(.vertical, DesignTokens.Spacing.xs)
                                    .background(selectedFilter == filter ? DesignTokens.Surface.selected : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .enchronGlassPill()
                            .contentShape(.hoverEffect, Capsule())
                            .hoverEffect(.automatic)
                        }
                    }
                }

                labeledComponent("Breadcrumb") {
                    MockBreadcrumb()
                }
            }
        }
    }

    @ViewBuilder
    private func badgeItem(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.badge)
            .foregroundStyle(.secondary)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .enchronGlassBadge()
    }
}

// MARK: - Player components

private struct PlayerSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("PLAYER CONTROLS")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            labeledComponent("ProgressBar · hover reveals scrubber · played / unplayed") {
                PlayerProgressStrip()
            }

            labeledComponent("PlayerControlBar · SF Symbols · token layout") {
                PlayerControlBar()
            }
        }
    }
}

// MARK: - Helper

@ViewBuilder
private func labeledComponent<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: DesignTokens.Spacing.xs) {
        content()
        Text(label)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }
}
