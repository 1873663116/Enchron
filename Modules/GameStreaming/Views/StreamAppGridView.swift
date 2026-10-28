import DesignSystem
import SwiftUI

struct StreamAppGridView: View {
    private enum PreferredEntry {
        case bigPicture
        case desktop

        var title: String {
            switch self {
            case .bigPicture: "Steam Big Picture"
            case .desktop: String(localized: "桌面")
            }
        }

        var keyword: String {
            switch self {
            case .bigPicture: "big picture"
            case .desktop: "desktop"
            }
        }

        var symbol: String {
            switch self {
            case .bigPicture: "gamecontroller"
            case .desktop: "display"
            }
        }

        var cardIdentifier: String {
            switch self {
            case .bigPicture: "Stream-AppCard-BigPicture"
            case .desktop: "Stream-AppCard-Desktop"
            }
        }

        var missingIdentifier: String {
            switch self {
            case .bigPicture: "Stream-AppMissing-BigPicture"
            case .desktop: "Stream-AppMissing-Desktop"
            }
        }
    }

    private struct Matches {
        var bigPicture: HostApplication?
        var desktop: HostApplication?
        var others: [HostApplication] = []
    }

    let state: HostApplicationsState
    let artworkURL: (AppID) -> URL?
    let hiddenAppIDs: Set<String>
    let onLaunch: (HostApplication) -> Void
    let onRemove: (HostApplication) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Stream-AppGrid")
        .accessibilityValue(gridValue)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .unknown:
            posters {
                GridCard.skeleton(.poster)
                GridCard.skeleton(.poster)
                GridCard.skeleton(.poster)
            }
        case .failed(let detail):
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                Text("应用列表读取失败，请确认主机已配对并在线。")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.supportingText)
                    .accessibilityValue(detail)
                preferredEntries(Matches())
            }
        case .loaded(let applications):
            preferredEntries(matched(applications))
        }
    }

    private func preferredEntries(_ matches: Matches) -> some View {
        posters {
            if let bigPicture = matches.bigPicture {
                card(bigPicture, identifier: PreferredEntry.bigPicture.cardIdentifier)
            } else {
                missingEntry(.bigPicture)
            }
            if let desktop = matches.desktop {
                card(desktop, identifier: PreferredEntry.desktop.cardIdentifier)
            } else {
                missingEntry(.desktop)
            }
            ForEach(matches.others.filter { hiddenAppIDs.contains($0.id.rawValue) == false }) { application in
                card(application, identifier: "Stream-AppCard-\(application.id.rawValue)")
            }
        }
    }

    private func posters<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            CardGrid {
                content()
            }
        }
        .scrollIndicators(.hidden)
    }

    private func card(_ application: HostApplication, identifier: String) -> some View {
        GridCard.poster(
            title: application.name,
            artworkURL: artworkURL(application.id),
            accessibilityIdentifier: identifier,
            action: { onLaunch(application) }
        )
        .accessibilityValue(application.name)
        .contextMenu {
            Button("移除主机应用卡片", role: .destructive) {
                onRemove(application)
            }
            .accessibilityIdentifier("Stream-AppCard-remove-\(application.id.rawValue)")
        }
    }

    private var posterHeight: CGFloat {
        DesignTokens.Card.posterWidth * 3 / 2
    }

    private func missingEntry(_ entry: PreferredEntry) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Image(systemName: entry.symbol)
                .font(DesignTokens.SymbolSize.card)
                .foregroundStyle(DesignTokens.Surface.supportingText)
            Text(entry.title)
                .font(DesignTokens.Typography.headline)
                .lineLimit(2)
            Text("主机未提供该条目")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.Surface.supportingText)
        }
        .padding(DesignTokens.Spacing.md)
        .frame(
            width: DesignTokens.Card.posterWidth,
            height: posterHeight,
            alignment: .topLeading
        )
        .enchronCardSurface(in: DesignTokens.ShapeToken.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.title)
        .accessibilityValue("missing")
        .accessibilityIdentifier(entry.missingIdentifier)
    }

    private func matched(_ applications: [HostApplication]) -> Matches {
        var matches = Matches()
        var claimed: Set<AppID> = []
        matches.bigPicture = firstMatch(applications, keyword: PreferredEntry.bigPicture.keyword, claimed: &claimed)
        matches.desktop = firstMatch(applications, keyword: PreferredEntry.desktop.keyword, claimed: &claimed)
        matches.others = applications.filter { claimed.contains($0.id) == false }
        return matches
    }

    private func firstMatch(
        _ applications: [HostApplication],
        keyword: String,
        claimed: inout Set<AppID>
    ) -> HostApplication? {
        guard let application = applications.first(where: {
            claimed.contains($0.id) == false && $0.name.lowercased().contains(keyword)
        }) else {
            return nil
        }
        claimed.insert(application.id)
        return application
    }

    private var gridValue: String {
        switch state {
        case .unknown:
            return "apps=loading"
        case .failed:
            return "apps=unavailable"
        case .loaded(let applications):
            let matches = matched(applications)
            let preferred = [matches.bigPicture, matches.desktop].compactMap { $0 }.count
            return "apps=\(applications.count);preferred=\(preferred);missing=\(2 - preferred)"
        }
    }
}
