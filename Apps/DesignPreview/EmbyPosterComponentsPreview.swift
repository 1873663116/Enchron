import DesignSystem
import Emby
import SwiftUI

struct EmbyPosterComponentsPreview: View {
    var body: some View {
        ScrollView {
            EmbyShelf(title: "Twelve fixture posters") {
                ForEach(Fixtures.shelf) { item in
                    GridCard.poster(
                        title: item.title,
                        artworkURL: nil,
                        watchedProgress: item.progress,
                        unplayedCount: item.unplayedCount
                    )
                }
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Emby Poster Shelf")
    }
}

private enum Fixtures {
    static let shelf: [PosterFixture] = [
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
    ) -> PosterFixture {
        PosterFixture(
            id: id,
            title: title,
            progress: progress,
            unplayedCount: unplayedCount
        )
    }
}

private struct PosterFixture: Identifiable {
    let id: String
    let title: String
    let progress: Double?
    let unplayedCount: Int?
}
