import SwiftUI

// MARK: - Browse Mockup
// App opening page mockup: floating window with sidebar + main content.

private let browseThemeColor = Color(red: 0.224, green: 0.773, blue: 0.733)
private let browseIconColor = Color.white

struct BrowseMockupView: View {
    var body: some View {
        NavigationSplitView {
            BrowseSidebar()
        } detail: {
            BrowseMainContent()
        }
        .navigationSplitViewStyle(.balanced)
    }
}

#Preview(windowStyle: .automatic) {
    BrowseMockupView()
}

// MARK: - Sidebar

private struct BrowseSidebar: View {
    @State private var selection: SourceItem? = .local

    private enum SourceItem: String, CaseIterable, Identifiable {
        case local
        case smb
        case webdav
        case photoLibrary

        var id: String { rawValue }

        var title: String {
            switch self {
            case .local: return "Local Storage"
            case .smb: return "SMB"
            case .webdav: return "WebDAV"
            case .photoLibrary: return "Photo Library"
            }
        }

        var icon: String {
            switch self {
            case .local: return "internaldrive"
            case .smb: return "network"
            case .webdav: return "globe"
            case .photoLibrary: return "photo.on.rectangle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    ForEach(SourceItem.allCases) { item in
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: item.icon)
                                .foregroundStyle(browseIconColor)
                            Text(item.title)
                        }
                            .tag(item)
                            .accessibilityIdentifier("DesignPreview-Browse-sidebar-source-\(item.rawValue)")
                            .accessibilityLabel(item.title)
                    }
                }
            }
            .navigationTitle("Sources")

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack {
                    Text("Storage")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("126 GB / 512 GB")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: 126, total: 512)
                    .tint(browseThemeColor)
                    .scaleEffect(x: 1, y: 1.6, anchor: .center)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .padding(.bottom, DesignTokens.Spacing.lg)
        }
    }
}

// MARK: - Main content

private struct MockFolderEntry {
    let name: String
    let itemCount: Int
}

private struct MockVideoEntry: Identifiable {
    let id = UUID()
    let title: String
    let size: String
    let duration: String
    let badges: [String]
    let metadata: String
}

private struct MockFolderContent {
    let folders: [MockFolderEntry]
    let videos: [MockVideoEntry]
}

private struct BrowseMainContent: View {
    @State private var viewMode = 0
    @State private var currentPath = ["Local Storage", "Movies"]
    @State private var selectedVideoTitle: String?

    private var folderMap: [String: MockFolderContent] {
        [
            "Local Storage/Movies": MockFolderContent(
                folders: [
                    MockFolderEntry(name: "Sci-Fi", itemCount: 3),
                    MockFolderEntry(name: "TV Shows", itemCount: 3)
                ],
                videos: [
                    MockVideoEntry(
                        title: "Blade Runner 2049",
                        size: "5.3 GB",
                        duration: "2:44:00",
                        badges: ["4K", "HDR10+"],
                        metadata: "4K · 5.3 GB"
                    ),
                    MockVideoEntry(
                        title: "Dune Part Two",
                        size: "4.1 GB",
                        duration: "2:46:00",
                        badges: ["DV"],
                        metadata: "4K · 4.1 GB"
                    )
                ]
            ),
            "Local Storage/Movies/Sci-Fi": MockFolderContent(
                folders: [],
                videos: [
                    MockVideoEntry(
                        title: "Interstellar",
                        size: "8.2 GB",
                        duration: "2:49:00",
                        badges: ["HDR10+"],
                        metadata: "4K · 8.2 GB"
                    ),
                    MockVideoEntry(
                        title: "The Matrix",
                        size: "2.1 GB",
                        duration: "2:16:00",
                        badges: [],
                        metadata: "1080p · 2.1 GB"
                    )
                ]
            ),
            "Local Storage/Movies/TV Shows": MockFolderContent(
                folders: [
                    MockFolderEntry(name: "Severance", itemCount: 2)
                ],
                videos: [
                    MockVideoEntry(
                        title: "Foundation S01E01",
                        size: "1.8 GB",
                        duration: "0:58:00",
                        badges: [],
                        metadata: "4K · 1.8 GB"
                    )
                ]
            ),
            "Local Storage/Movies/TV Shows/Severance": MockFolderContent(
                folders: [],
                videos: [
                    MockVideoEntry(
                        title: "Severance S01E01",
                        size: "1.6 GB",
                        duration: "0:57:00",
                        badges: [],
                        metadata: "4K · 1.6 GB"
                    ),
                    MockVideoEntry(
                        title: "Severance S01E02",
                        size: "1.7 GB",
                        duration: "0:51:00",
                        badges: [],
                        metadata: "4K · 1.7 GB"
                    )
                ]
            )
        ]
    }

    private var currentContent: MockFolderContent {
        let key = currentPath.joined(separator: "/")
        return folderMap[key] ?? MockFolderContent(folders: [], videos: [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            BrowseToolbar(
                viewMode: $viewMode,
                currentPath: $currentPath
            )
            MockFilterBar()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    if let selectedVideoTitle {
                        Text("Selected: \(selectedVideoTitle)")
                            .font(DesignTokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                    }

                    if viewMode == 0 {
                        Text("CARD MODE")
                            .font(DesignTokens.Typography.sectionHeader)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        MockCardGrid(
                            folders: currentContent.folders,
                            videos: currentContent.videos,
                            onOpenFolder: { folderName in
                                currentPath.append(folderName)
                            },
                            onOpenVideo: { video in
                                selectedVideoTitle = video.title
                            }
                        )
                    } else {
                        Text("LIST MODE")
                            .font(DesignTokens.Typography.sectionHeader)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        MockFileList(
                            folders: currentContent.folders,
                            videos: currentContent.videos,
                            onOpenFolder: { folderName in
                                currentPath.append(folderName)
                            },
                            onOpenVideo: { video in
                                selectedVideoTitle = video.title
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DesignTokens.Spacing.lg)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Toolbar

private struct BrowseToolbar: View {
    @Binding var viewMode: Int
    @Binding var currentPath: [String]

    @State private var searchText = ""
    @State private var sortKey: SortKey = .name
    @State private var sortOrder: SortOrder = .ascending
    @FocusState private var isSearchFocused: Bool

    private enum SortKey {
        case name
        case modifiedDate
        case size
    }

    private enum SortOrder {
        case ascending
        case descending
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            NavBackForwardCapsuleControl(
                iconColor: browseIconColor,
                accessibilityIdentifier: "DesignPreview-Browse-toolbar-control-navBackForward"
            )
            MockBreadcrumb(
                path: currentPath,
                onSelectLevel: { index in
                    guard index < currentPath.count else { return }
                    currentPath = Array(currentPath.prefix(index + 1))
                }
            )

            Spacer()

            ViewModeCapsuleControl(
                selection: $viewMode,
                iconColor: browseIconColor,
                accessibilityIdentifier: "DesignPreview-Browse-toolbar-control-viewMode"
            )
            sortMenuButton
            sourceMenuButton
            searchInputCapsule
        }
    }

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
                .foregroundStyle(browseIconColor)
                .frame(width: DesignTokens.Interactive.regular,
                       height: DesignTokens.Interactive.regular)
                .clipShape(Circle())
                .glassBackgroundEffect(in: Circle())
                .contentShape(.hoverEffect, Circle())
                .hoverEffect(.automatic)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DesignPreview-Browse-toolbar-menu-sort")
        .accessibilityLabel("Sort Menu")
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
                .foregroundStyle(browseIconColor)
                .frame(width: DesignTokens.Interactive.regular,
                       height: DesignTokens.Interactive.regular)
                .clipShape(Circle())
                .glassBackgroundEffect(in: Circle())
                .contentShape(.hoverEffect, Circle())
                .hoverEffect(.automatic)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DesignPreview-Browse-toolbar-menu-source")
        .accessibilityLabel("Source Menu")
    }

    private var searchInputCapsule: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(browseIconColor)

            TextField("搜索", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .tint(browseThemeColor)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(width: 280, height: DesignTokens.Interactive.regular)
        .clipShape(Capsule())
        .glassBackgroundEffect(in: Capsule())
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.automatic)
        .contentShape(Capsule())
        .onTapGesture {
            isSearchFocused = true
        }
        .accessibilityIdentifier("DesignPreview-Browse-toolbar-input-search")
        .accessibilityLabel("Search")
    }
}

// MARK: - Breadcrumb

struct MockBreadcrumb: View {
    let path: [String]
    let onSelectLevel: (Int) -> Void

    init(
        path: [String] = ["Local Storage", "Movies"],
        onSelectLevel: @escaping (Int) -> Void = { _ in }
    ) {
        self.path = path
        self.onSelectLevel = onSelectLevel
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            ForEach(Array(path.enumerated()), id: \.offset) { index, node in
                Button(node) {
                    onSelectLevel(index)
                }
                .buttonStyle(.plain)
                .font(.body)
                .foregroundStyle(.secondary)
                .contentShape(.hoverEffect, Capsule())
                .hoverEffect(.lift)
                .contentShape(Capsule())

                if index < path.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(browseIconColor.opacity(0.8))
                }
            }
        }
    }
}

// MARK: - Filter pills

private struct MockFilterBar: View {
    @State private var selected = "All"
    private let filters = ["All", "Movies", "TV Shows", "Concerts"]

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(filters, id: \.self) { filter in
                Button { selected = filter } label: {
                    Text(filter)
                        .font(.body)
                        .foregroundStyle(selected == filter ? .primary : .secondary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .background(selected == filter ? DesignTokens.Surface.selected : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .enchronGlassPill()
                .contentShape(.hoverEffect, Capsule())
                .hoverEffect(.automatic)
            }
            Spacer()
        }
    }
}

// MARK: - Card grid

private struct MockCardGrid: View {
    let folders: [MockFolderEntry]
    let videos: [MockVideoEntry]
    let onOpenFolder: (String) -> Void
    let onOpenVideo: (MockVideoEntry) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Card.gridSpacing) {
            ForEach(folders, id: \.name) { folder in
                Button {
                    onOpenFolder(folder.name)
                } label: {
                    FolderCard(title: folder.name, count: folder.itemCount)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("DesignPreview-Browse-folderCard-\(folder.name)")
                .accessibilityLabel("Open folder \(folder.name)")
            }

            ForEach(videos) { video in
                Button {
                    onOpenVideo(video)
                } label: {
                    VideoCardLarge(
                        title: video.title,
                        fileSize: video.size,
                        duration: video.duration,
                        badges: video.badges
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("DesignPreview-Browse-videoCard-\(video.title)")
                .accessibilityLabel("Play \(video.title)")
            }
        }
    }
}

// MARK: - File list rows

private struct MockFileList: View {
    let folders: [MockFolderEntry]
    let videos: [MockVideoEntry]
    let onOpenFolder: (String) -> Void
    let onOpenVideo: (MockVideoEntry) -> Void

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            ForEach(folders, id: \.name) { folder in
                Button {
                    onOpenFolder(folder.name)
                } label: {
                    FileListRow(icon: "folder", title: folder.name, metadata: "\(folder.itemCount) items")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("DesignPreview-Browse-folderRow-\(folder.name)")
                .accessibilityLabel("Open folder \(folder.name)")
            }

            ForEach(videos) { video in
                Button {
                    onOpenVideo(video)
                } label: {
                    FileListRow(icon: "film", title: video.title, metadata: video.metadata)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("DesignPreview-Browse-videoRow-\(video.title)")
                .accessibilityLabel("Play \(video.title)")
            }
        }
    }
}
