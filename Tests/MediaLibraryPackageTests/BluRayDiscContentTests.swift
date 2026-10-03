import BluRayDisc
import Foundation
@testable import MediaLibrary
import Testing

struct BluRayDiscContentTests {
    @Test("one authored program becomes one source-named film")
    func singleFilm() throws {
        let catalog = BluRayDiscCatalog(titles: [
            title(7, seconds: 119.911444, clips: [clip("00001", seconds: 119.911444)])
        ])

        let content = try BluRayDiscContent.project(catalog, sourceName: "FEL_test_for_AVS.iso")

        #expect(content.name == "FEL_test_for_AVS")
        #expect(content.primaryTitles.map(\.playlistID.rawValue) == [7])
        #expect(content.primaryTitles.map(\.displayName) == ["FEL_test_for_AVS"])
        #expect(content.groups.isEmpty)
        guard case .feature = content else {
            Issue.record("A single motion program must be a film")
            return
        }
    }

    @Test("disc metadata names the film and a verified title name remains visible")
    func authoredNaming() throws {
        let catalog = BluRayDiscCatalog(
            titles: [title(4, seconds: 120, name: "  Opening film  ",
                           clips: [clip("00004", seconds: 120)])],
            optionalName: "  Author's disc  "
        )

        let content = try BluRayDiscContent.project(catalog, sourceName: "Container.iso")

        #expect(content.name == "Author's disc")
        #expect(content.primaryTitles.map(\.displayName) == ["Opening film"])
        #expect(content.primaryTitles.map(\.playlistID.rawValue) == [4])
    }

    @Test("ordered shared clip intervals preserve a distinct complete edition")
    func editions() throws {
        let original = title(
            10, seconds: 100, isMain: true,
            clips: [clip("A", seconds: 60), clip("B", seconds: 40, start: 60)]
        )
        let longer = title(
            20, seconds: 110,
            clips: [clip("A", seconds: 60), clip("X", seconds: 10, start: 60),
                    clip("B", seconds: 40, start: 70)]
        )

        let content = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: [longer, original]), sourceName: "Feature.iso"
        )

        #expect(content.name == "Feature")
        #expect(content.primaryTitles.map(\.playlistID.rawValue) == [10, 20])
        #expect(content.primaryTitles.map(\.displayName) == [
            "1m 40s · Feature", "1m 50s · Feature"
        ])
        #expect(content.groups.isEmpty)
    }

    @Test("one physical clip split into authored intervals still matches an edition")
    func splitClipEdition() throws {
        let original = title(
            3, seconds: 150, isMain: true,
            clips: [clip("A", seconds: 100), clip("B", seconds: 50, start: 100)]
        )
        let edited = title(
            4, seconds: 160,
            clips: [clip("A", seconds: 40), clip("X", seconds: 10, start: 40),
                    clip("A", seconds: 60, start: 50, inPoint: 40),
                    clip("B", seconds: 50, start: 110)]
        )

        let content = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: [edited, original]), sourceName: "Film"
        )

        #expect(content.primaryTitles.map(\.playlistID.rawValue) == [3, 4])
        #expect(content.primaryTitles.map(\.displayName) == [
            "2m 30s · Film", "2m 40s · Film"
        ])
    }

    @Test("90 kHz atom boundaries match split fractions without floating-point equality")
    func tickExactSplit() throws {
        let fullSeconds = Double(90_090) / 90_000
        let firstSeconds = Double(45_045) / 90_000
        let original = title(1, seconds: fullSeconds,
                             clips: [clip("A", seconds: fullSeconds)])
        let split = title(2, seconds: fullSeconds,
                          clips: [clip("A", seconds: firstSeconds),
                                  clip("A", seconds: firstSeconds,
                                       start: firstSeconds, inPoint: firstSeconds)])

        let content = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: [split, original]), sourceName: "Film"
        )

        #expect(content.primaryTitles.map(\.playlistID.rawValue) == [1])
        #expect(content.groups.map(\.kind) == [.additional])
        #expect(content.groups.flatMap(\.titles).map(\.playlistID.rawValue) == [2])
    }

    @Test("repeating one partial interval cannot count the same footage twice")
    func repeatedPartialInterval() throws {
        let complete = title(1, seconds: 100, clips: [clip("A", seconds: 100)])
        let repeated = title(2, seconds: 100,
                             clips: [clip("A", seconds: 50),
                                     clip("A", seconds: 50, start: 50)])

        let content = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: [complete, repeated]), sourceName: "Programs"
        )

        #expect(content.primaryTitles.isEmpty)
        #expect(content.groups.map(\.kind) == [.videos, .sequences])
        #expect(content.groups.flatMap(\.titles).map(\.playlistID.rawValue) == [1, 2])
    }

    @Test("a short contained route stays outside the edition picker")
    func shortSubset() throws {
        let film = title(
            1, seconds: 100,
            clips: [clip("A", seconds: 60), clip("B", seconds: 40, start: 60)]
        )
        let excerpt = title(2, seconds: 10, clips: [clip("A", seconds: 10)])

        let content = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: [excerpt, film]), sourceName: "Film"
        )

        #expect(content.primaryTitles.map(\.playlistID.rawValue) == [1])
        #expect(content.groups.map(\.kind) == [.additional])
        #expect(content.groups.flatMap(\.titles).map(\.playlistID.rawValue) == [2])
        #expect(content.groups.flatMap(\.titles).map(\.displayName) == [
            "Videos · 10s · H.264 1080p"
        ])
    }

    @Test("unrelated long programs make a collection even when one is marked main")
    func independentLongPrograms() throws {
        let first = title(9, seconds: 100, clips: [clip("A", seconds: 100)])
        let second = title(3, seconds: 100, isMain: true,
                           clips: [clip("B", seconds: 100)])

        let content = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: [second, first]), sourceName: "Programs.iso"
        )

        #expect(content.name == "Programs")
        #expect(content.primaryTitles.isEmpty)
        #expect(content.groups.map(\.kind) == [.videos])
        #expect(content.groups[0].titles.map(\.playlistID.rawValue) == [9, 3])
        #expect(content.groups[0].titles.map(\.isMain) == [false, false])
        #expect(content.groups[0].titles.map(\.displayName) == [
            "Item 1 · Videos · 1m 40s · H.264 1080p",
            "Item 2 · Videos · 1m 40s · H.264 1080p"
        ])
        guard case .collection = content else {
            Issue.record("Independent programs must not appear as editions")
            return
        }
    }

    @Test("sharing clips in a different order does not by itself create an edition")
    func reorderedClips() throws {
        let first = title(1, seconds: 100,
                          clips: [clip("A", seconds: 50), clip("B", seconds: 50, start: 50)])
        let reversed = title(2, seconds: 100,
                             clips: [clip("B", seconds: 50), clip("A", seconds: 50, start: 50)])

        let content = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: [reversed, first]), sourceName: "Programs"
        )

        #expect(content.primaryTitles.isEmpty)
        #expect(content.groups.map(\.kind) == [.sequences])
        #expect(content.groups.flatMap(\.titles).map(\.playlistID.rawValue) == [1, 2])
    }

    @Test("two complete edits with reordered footage keep distinct equal-length names")
    func sameLengthReorderedEdits() throws {
        let first = title(1, seconds: 120, isMain: true,
                          clips: [clip("A", seconds: 40),
                                  clip("B", seconds: 40, start: 40),
                                  clip("C", seconds: 40, start: 80)])
        let reordered = title(2, seconds: 120,
                              clips: [clip("A", seconds: 40),
                                      clip("C", seconds: 40, start: 40),
                                      clip("B", seconds: 40, start: 80)])

        let content = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: [reordered, first]), sourceName: "Feature"
        )

        #expect(content.primaryTitles.map(\.playlistID.rawValue) == [1, 2])
        #expect(content.primaryTitles.map(\.displayName) == [
            "2m 00s · Version 1 · Feature",
            "2m 00s · Version 2 · Feature"
        ])
    }

    @Test("a tiny main marker does not override an independent feature")
    func misleadingMain() throws {
        let movie = title(8, seconds: 100, clips: [clip("F", seconds: 100)])
        let menu = title(4, seconds: 2, isMain: true,
                         clips: [clip("M", seconds: 2, interactive: true)])

        let content = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: [menu, movie]), sourceName: "Film.iso"
        )

        #expect(content.primaryTitles.map(\.playlistID.rawValue) == [8])
        #expect(content.primaryTitles.map(\.displayName) == ["Film"])
        #expect(content.groups.map(\.kind) == [.additional])
        #expect(content.groups.flatMap(\.titles).map(\.playlistID.rawValue) == [4])
    }

    @Test("one film and independent short navigation and bonus routes remain one film")
    func filmWithShortIndependentContent() throws {
        let film = title(0, seconds: 888, isMain: true,
                         clips: [clip("MOVIE", seconds: 888)])
        let navigation = title(1_900, seconds: 0.458777,
                               clips: [clip("MENU", seconds: 0.458777,
                                            interactive: true)])
        let bonus = title(2_001, seconds: 45, name: "Production notes",
                          clips: [clip("BONUS", seconds: 45)])

        let content = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: [bonus, navigation, film]), sourceName: "Sintel.iso"
        )

        #expect(content.name == "Sintel")
        #expect(content.primaryTitles.map(\.playlistID.rawValue) == [0])
        #expect(content.primaryTitles.map(\.displayName) == ["Sintel"])
        #expect(content.groups.map(\.kind) == [.additional])
        #expect(content.groups.flatMap(\.titles).map(\.playlistID.rawValue) == [2_001, 1_900])
        #expect(content.groups.flatMap(\.titles).map(\.displayName) == [
            "Production notes", "Videos · 0.459s · H.264 1080p"
        ])
    }

    @Test("a still program is discoverable without becoming a film")
    func stillImages() throws {
        let still = title(11, seconds: 15,
                          clips: [clip("S", seconds: 15, stillMode: 2)])

        let content = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: [still]), sourceName: "Gallery"
        )

        #expect(content.primaryTitles.isEmpty)
        #expect(content.groups.map(\.kind) == [.stillImages])
        #expect(content.groups.flatMap(\.titles).map(\.playlistID.rawValue) == [11])
        #expect(content.groups.flatMap(\.titles).map(\.displayName) == [
            "Still images · 15s · H.264 1080p"
        ])
    }

    @Test("empty and whitespace names use an honest source fallback")
    func sourceFallback() throws {
        let catalog = BluRayDiscCatalog(
            titles: [title(1, seconds: 60, clips: [clip("A", seconds: 60)])],
            optionalName: "  "
        )

        let image = try BluRayDiscContent.project(catalog, sourceName: "  My Film.ISO  ")
        let root = try BluRayDiscContent.project(catalog, sourceName: "My Film")
        let unnamed = try BluRayDiscContent.project(catalog, sourceName: "   ")

        #expect(image == root)
        #expect(image.name == "My Film")
        #expect(unnamed.name == "Blu-ray disc")
        #expect(unnamed.primaryTitles.map(\.displayName) == ["Blu-ray disc"])
    }

    @Test("catalog order cannot change program identity or visible labels")
    func orderIndependent() throws {
        let titles = [
            title(12, seconds: 60, clips: [clip("B", seconds: 60)]),
            title(4, seconds: 60, clips: [clip("A", seconds: 60)]),
            title(9, seconds: 2, clips: [clip("C", seconds: 2, stillMode: 1)])
        ]

        let forward = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: titles), sourceName: "Programs"
        )
        let reversed = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: Array(titles.reversed())), sourceName: "Programs"
        )

        #expect(forward == reversed)
        #expect(forward.primaryTitles.isEmpty)
        #expect(forward.groups.map(\.kind) == [.videos, .stillImages])
        #expect(forward.groups.flatMap(\.titles).map(\.playlistID.rawValue) == [4, 12, 9])
    }

    @Test("an exact duplicate route is available only under additional content")
    func duplicateRoute() throws {
        let original = title(1, seconds: 100, clips: [clip("A", seconds: 100)])
        let duplicate = title(2, seconds: 100, clips: [clip("A", seconds: 100)])

        let content = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: [duplicate, original]), sourceName: "Film"
        )

        #expect(content.primaryTitles.map(\.playlistID.rawValue) == [1])
        #expect(content.groups.map(\.kind) == [.additional])
        #expect(content.groups.flatMap(\.titles).map(\.playlistID.rawValue) == [2])
    }

    @Test("the same video route with different audio stays reachable once as a film")
    func sameVideoDifferentAudio() throws {
        let english = title(1, seconds: 100,
                            clips: [clip("A", seconds: 100, audioLanguage: "eng")])
        let french = title(2, seconds: 100,
                           clips: [clip("A", seconds: 100, audioLanguage: "fra")])

        let content = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: [french, english]), sourceName: "Film"
        )

        #expect(content.primaryTitles.map(\.playlistID.rawValue) == [1])
        #expect(content.primaryTitles.map(\.displayName) == ["Film"])
        #expect(content.groups.map(\.kind) == [.additional])
        #expect(content.groups.flatMap(\.titles).map(\.playlistID.rawValue) == [2])
    }

    @Test("interactive graphics alone do not demote a long movie with audio")
    func longVideoWithInteractiveGraphics() throws {
        let movie = title(1, seconds: 888, isMain: true,
                          clips: [clip("MOVIE", seconds: 888,
                                       interactive: true, audioLanguage: "eng")])
        let menu = title(2, seconds: 0.458777,
                         clips: [clip("MENU", seconds: 0.458777, interactive: true)])

        let content = try BluRayDiscContent.project(
            BluRayDiscCatalog(titles: [menu, movie]), sourceName: "Film"
        )

        #expect(content.primaryTitles.map(\.playlistID.rawValue) == [1])
        #expect(content.primaryTitles.map(\.displayName) == ["Film"])
        #expect(content.groups.map(\.kind) == [.additional])
        #expect(content.groups.flatMap(\.titles).map(\.playlistID.rawValue) == [2])
    }

    @Test("the authored calibration disc is a collection, while the FEL disc is one film")
    func authoredCorpusProjection() throws {
        let sampleRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "TestMedia/Samples/DiscImages")
        let avs = try BluRayDisc.catalog(at: sampleRoot.appending(
            path: "AVS-HD-709/HDMV-2d.iso"
        ))
        let fel = try BluRayDisc.catalog(at: sampleRoot.appending(
            path: "DolbyVision-Profile7-FEL/FEL_test_for_AVS.iso"
        ))

        let collection = try BluRayDiscContent.project(avs, sourceName: "HDMV-2d.iso")
        let film = try BluRayDiscContent.project(fel, sourceName: "FEL_test_for_AVS.iso")

        #expect(collection.name == "HDMV-2d")
        #expect(collection.primaryTitles.isEmpty)
        #expect(collection.groups.map(\.kind) == [.videos, .sequences, .stillImages])
        #expect(collection.groups.map { $0.titles.count } == [97, 2, 11])
        #expect(collection.groups.flatMap(\.titles).count == 110)
        #expect(collection.groups.flatMap(\.titles).map(\.playlistID.rawValue).contains(99))
        #expect(collection.groups.flatMap(\.titles).map(\.playlistID.rawValue).contains(109))
        #expect(collection.groups.flatMap(\.titles).allSatisfy {
            !$0.displayName.contains("Playlist")
        })
        #expect(film.name == "FEL_test_for_AVS")
        #expect(film.primaryTitles.map(\.playlistID.rawValue) == [0])
        #expect(film.primaryTitles.map(\.displayName) == ["FEL_test_for_AVS"])
    }

    @Test("official Sintel ISO and directory show one film plus one additional route")
    func officialSintelSources() throws {
        let root = sampleRoot.appending(path: "Sintel")
        let sources = [
            root.appending(path: "Sintel-Bluray.iso"),
            root.appending(path: "Sintel-Bluray")
        ]
        let contents = try sources.map { source in
            try BluRayDiscContent.project(
                BluRayDisc.catalog(at: source), sourceName: "Sintel-Bluray"
            )
        }

        #expect(contents[0] == contents[1])
        #expect(contents[0].name == "Sintel-Bluray")
        #expect(contents[0].primaryTitles.map(\.playlistID.rawValue) == [0])
        #expect(contents[0].primaryTitles.map(\.displayName) == ["Sintel-Bluray"])
        #expect(contents[0].groups.map(\.kind) == [.additional])
        #expect(contents[0].groups.flatMap(\.titles).map(\.playlistID.rawValue) == [1_900])
    }

    @Test("authored 60s and 75s editions agree for ISO and directory")
    func controlledEditionSources() throws {
        let root = sampleRoot.appending(path: "Sintel-Editions")
        let sources = [
            root.appending(path: "Sintel-Editions.iso"),
            root.appending(path: "Sintel-Editions")
        ]
        let contents = try sources.map { source in
            try BluRayDiscContent.project(
                BluRayDisc.catalog(at: source), sourceName: "Sintel-Editions"
            )
        }

        #expect(contents[0] == contents[1])
        #expect(contents[0].name == "Sintel – Edition tests")
        #expect(contents[0].primaryTitles.map(\.playlistID.rawValue) == [1, 0])
        #expect(contents[0].primaryTitles.map(\.displayName) == [
            "1m 15s · Sintel – Edition tests", "1m 00s · Sintel – Edition tests"
        ])
        #expect(contents[0].groups.map(\.kind) == [.additional])
        #expect(contents[0].groups.flatMap(\.titles).map(\.playlistID.rawValue) == [2])
    }

    @Test("an empty catalog fails instead of presenting an empty shelf")
    func emptyCatalog() {
        #expect(throws: BluRayDiscError.self) {
            try BluRayDiscContent.project(BluRayDiscCatalog(titles: []), sourceName: "Empty")
        }
    }

    private func title(
        _ id: UInt32,
        seconds: Double,
        name: String? = nil,
        isMain: Bool = false,
        clips: [BluRayClip]
    ) -> BluRayDiscTitle {
        BluRayDiscTitle(
            playlistID: BluRayPlaylistID(rawValue: id),
            ordinal: Int(id),
            optionalName: name,
            durationSeconds: seconds,
            isMain: isMain,
            clips: clips
        )
    }

    private var sampleRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "TestMedia/Samples/DiscImages")
    }

    private func clip(
        _ id: String,
        seconds: Double,
        start: Double = 0,
        inPoint: Double = 0,
        stillMode: UInt8 = 0,
        interactive: Bool = false,
        audioLanguage: String? = nil
    ) -> BluRayClip {
        var streams = [BluRayStream(
            pid: 4_113,
            codingType: 27,
            kind: .video,
            language: nil,
            format: 6
        )]
        if let audioLanguage {
            streams.append(BluRayStream(
                pid: 4_352,
                codingType: 129,
                kind: .audio,
                language: audioLanguage
            ))
        }
        return BluRayClip(
            clipID: id,
            startTimeSeconds: start,
            inTimeSeconds: inPoint,
            outTimeSeconds: inPoint + seconds,
            byteStart: 0,
            byteEnd: 192_000,
            packetCount: 1_000,
            streams: streams,
            stillMode: stillMode,
            hasInteractiveGraphics: interactive
        )
    }
}
