import SwiftUI

struct HomeFirstLaunchPage: View {
    @State private var searchText = ""

    private let videos = [
        FileVideo(title: "Interstellar", fileSize: "42.8 GB", duration: "2:28:14", badges: ["MV-HEVC", "HDR"]),
        FileVideo(title: "The Matrix", fileSize: "38.2 GB", duration: "2:43:07", badges: []),
        FileVideo(title: "Dune: Part Two", fileSize: "56.1 GB", duration: "2:44:31", badges: ["HDR10+"]),
        FileVideo(title: "Arrival", fileSize: "28.4 GB", duration: "1:49:22", badges: ["MV-HEVC"]),
        FileVideo(title: "Blade Runner 2049", fileSize: "45.6 GB", duration: "2:29:55", badges: []),
        FileVideo(title: "Ex Machina", fileSize: "22.7 GB", duration: "2:19:48", badges: ["Dolby Vision"]),
        FileVideo(title: "Gravity", fileSize: "18.9 GB", duration: "1:31:07", badges: ["MV-HEVC"]),
        FileVideo(title: "2001: A Space Odyssey", fileSize: "35.1 GB", duration: "2:29:00", badges: []),
        FileVideo(title: "The Martian", fileSize: "31.5 GB", duration: "2:24:11", badges: ["HDR10+"])
    ]

    private var gridMaxWidth: CGFloat {
        DesignTokens.Card.gridMin * 4 + DesignTokens.Card.gridSpacing * 3
    }

    var body: some View {
        HStack(spacing: 0) {
            sourcePane
            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignComps-HomeFirstLaunchPage")
        .accessibilityLabel("Files page")
    }

    private var sourcePane: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            sourceSection("Sources") {
                SourcePaneRow(icon: "externaldrive.fill", title: "Local Storage", isOnline: true)
                SourcePaneRow(icon: "server.rack", title: "NAS-01 (SMB)", isSelected: true, isOnline: true)
                SourcePaneRow(icon: "cloud.fill", title: "WebDAV", isEnabled: false)
            }

            Divider()
                .overlay(DesignTokens.Surface.border)

            sourceSection("Favorites") {
                SourcePaneRow(icon: "star.fill", title: "Starred Videos")
            }

            Spacer(minLength: 0)
            storageMeter
        }
        .padding(.vertical, DesignTokens.Spacing.xl)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(width: DesignTokens.SourcePane.width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DesignTokens.Surface.border)
                .frame(width: DesignTokens.Stroke.subtle)
        }
        .accessibilityIdentifier("DesignComps-FilesPage-sourcePane")
    }

    private var contentArea: some View {
        VStack(spacing: 0) {
            topBar
            itemCountBar
            videoGrid
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("DesignComps-FilesPage-contentArea")
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            NavBackForwardCapsuleControl(
                accessibilityIdentifier: "DesignComps-FilesPage-navBackForward"
            )
            breadcrumb
            Spacer(minLength: DesignTokens.Spacing.xl)
            searchField
        }
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    private var breadcrumb: some View {
        PathBreadcrumbMenu(path: ["Local Storage", "Movies"])
    }

    private var searchField: some View {
        SearchInputCapsule(
            text: $searchText,
            placeholder: "Search files...",
            accessibilityIdentifier: "DesignComps-FilesPage-search"
        )
    }

    private var itemCountBar: some View {
        HStack {
            Spacer()
            Text("\(videos.count) items")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    private var videoGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: DesignTokens.Card.gridMin
                        ),
                        spacing: DesignTokens.Card.gridSpacing
                    )
                ],
                alignment: .leading,
                spacing: DesignTokens.Card.gridSpacing
            ) {
                ForEach(videos) { video in
                    VideoCardLarge(
                        title: video.title,
                        fileSize: video.fileSize,
                        duration: video.duration,
                        badges: video.badges
                    )
                }
            }
            .frame(maxWidth: gridMaxWidth, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func sourceSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(spacing: DesignTokens.Spacing.xxs) {
                content()
            }
        }
    }

    private var storageMeter: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text("Storage")
                Spacer()
                Text("1.2 TB / 4 TB")
            }
            .font(DesignTokens.Typography.sectionHeader)
            .foregroundStyle(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignTokens.Surface.overlay)
                    Capsule()
                        .fill(DesignTokens.Theme.accent)
                        .frame(width: geometry.size.width * 0.3)
                }
            }
            .frame(height: DesignTokens.Spacing.xs)
        }
    }

}

private struct FileVideo: Identifiable {
    let title: String
    let fileSize: String
    let duration: String
    let badges: [String]

    var id: String { title }
}
