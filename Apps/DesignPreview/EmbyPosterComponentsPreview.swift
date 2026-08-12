import DesignSystem
import Emby
import SwiftUI

struct EmbyPosterComponentsPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    Text("Poster cards")
                        .font(DesignTokens.Typography.title)

                    HStack(alignment: .top, spacing: DesignTokens.Card.gridSpacing) {
                        fixtureCard(label: "Normal", item: Fixtures.normal)
                        fixtureCard(label: "In progress", item: Fixtures.inProgress)
                        fixtureCard(label: "Unplayed", item: Fixtures.unplayed)
                    }
                }

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    Text("Loading states")
                        .font(DesignTokens.Typography.title)

                    HStack(alignment: .top, spacing: DesignTokens.Card.gridSpacing) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            Text("Skeleton")
                                .font(DesignTokens.Typography.metadata)
                                .foregroundStyle(.secondary)
                            EmbyPosterSkeletonCard()
                        }

                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            Text("Async image, nil URL")
                                .font(DesignTokens.Typography.metadata)
                                .foregroundStyle(.secondary)
                            EmbyPosterCard(item: Fixtures.asyncPlaceholder) {
                                EmbyAsyncPosterImage(url: nil)
                            }
                        }
                    }
                }

                EmbyPosterShelf(
                    title: "Twelve fixture posters",
                    items: Fixtures.shelf
                ) { item in
                    EmbyPosterPlaceholder(title: item.title)
                }
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Emby Components")
    }

    private func fixtureCard(
        label: String,
        item: EmbyPosterItem
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(label)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
            EmbyPosterCard(item: item) {
                EmbyPosterPlaceholder(title: item.title)
            }
        }
    }
}

private enum Fixtures {
    static let normal = item("arrival", "Arrival")
    static let inProgress = item("dune", "Dune: Part Two", progress: 0.42)
    static let unplayed = item("severance", "Severance", unplayedCount: 5)
    static let asyncPlaceholder = item("async-placeholder", "Remote poster placeholder")

    static let shelf: [EmbyPosterItem] = [
        item("shelf-01", "Blade Runner 2049"),
        item("shelf-02", "The Grand Budapest Hotel"),
        item("shelf-03", "Spirited Away", progress: 0.18),
        item("shelf-04", "The Bear", unplayedCount: 3),
        item("shelf-05", "Past Lives"),
        item("shelf-06", "The Expanse", progress: 0.67),
        item("shelf-07", "Moonlight"),
        item("shelf-08", "Station Eleven", unplayedCount: 2),
        item("shelf-09", "Perfect Days"),
        item("shelf-10", "The Green Knight"),
        item("shelf-11", "Aftersun", progress: 0.31),
        item("shelf-12", "Scavengers Reign", unplayedCount: 6),
    ]

    private static func item(
        _ id: String,
        _ title: String,
        progress: Double? = nil,
        unplayedCount: Int? = nil
    ) -> EmbyPosterItem {
        EmbyPosterItem(
            id: EmbyItemID(rawValue: id),
            title: title,
            progress: progress,
            unplayedCount: unplayedCount
        )
    }
}
