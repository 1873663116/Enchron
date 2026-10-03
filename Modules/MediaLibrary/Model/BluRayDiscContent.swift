import BluRayDisc
import Foundation

public struct BluRayPresentedTitle: Identifiable, Sendable, Equatable {
    public let playlistID: BluRayPlaylistID
    public let displayName: String
    public let durationSeconds: Double
    public let isMain: Bool

    public var id: BluRayPlaylistID { playlistID }
}

public enum BluRayContentGroupKind: String, Identifiable, CaseIterable, Sendable {
    case videos
    case sequences
    case stillImages
    case additional

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .videos: String(localized: "Videos")
        case .sequences: String(localized: "Sequences")
        case .stillImages: String(localized: "Still images")
        case .additional: String(localized: "Additional content")
        }
    }
}

public struct BluRayContentGroup: Identifiable, Sendable, Equatable {
    public let kind: BluRayContentGroupKind
    public let titles: [BluRayPresentedTitle]

    public var id: BluRayContentGroupKind { kind }
}

public enum BluRayDiscContent: Sendable, Equatable {
    case feature(
        name: String,
        main: BluRayPresentedTitle,
        editions: [BluRayPresentedTitle],
        additional: [BluRayContentGroup]
    )
    case collection(name: String, groups: [BluRayContentGroup])

    public var name: String {
        switch self {
        case .feature(let name, _, _, _), .collection(let name, _): name
        }
    }

    public var primaryTitles: [BluRayPresentedTitle] {
        switch self {
        case .feature(_, let main, let editions, _): [main] + editions
        case .collection: []
        }
    }

    public var groups: [BluRayContentGroup] {
        switch self {
        case .feature(_, _, _, let additional): additional
        case .collection(_, let groups): groups
        }
    }

    public static func project(
        _ catalog: BluRayDiscCatalog,
        sourceName: String
    ) throws -> BluRayDiscContent {
        guard !catalog.titles.isEmpty else {
            throw BluRayDiscError.corrupt("The Blu-ray disc has no playable titles.")
        }
        var ids: Set<BluRayPlaylistID> = []
        let maximumTickSeconds = Double(Int64.max / 90_000) / 2
        for title in catalog.titles {
            guard ids.insert(title.playlistID).inserted,
                  title.durationSeconds.isFinite,
                  title.durationSeconds >= 0,
                  title.durationSeconds < maximumTickSeconds,
                  title.clips.allSatisfy({
                      $0.startTimeSeconds.isFinite &&
                          $0.inTimeSeconds.isFinite &&
                          $0.outTimeSeconds.isFinite &&
                          abs($0.startTimeSeconds) < maximumTickSeconds &&
                          abs($0.inTimeSeconds) < maximumTickSeconds &&
                          abs($0.outTimeSeconds) < maximumTickSeconds &&
                          $0.outTimeSeconds >= $0.inTimeSeconds
                  }) else {
                throw BluRayDiscError.corrupt("The Blu-ray title catalog is invalid.")
            }
        }

        let name = discName(authored: catalog.optionalName, source: sourceName)
        let ordered = catalog.titles.sorted(by: titlePrecedes)
        let duplicateIDs = duplicateRouteIDs(in: ordered)
        let candidates = ordered.filter {
            guard !duplicateIDs.contains($0.playlistID) else { return false }
            let category = kind(for: $0)
            return category == .videos || category == .sequences
        }

        guard let anchor = candidates.first else {
            return .collection(
                name: name,
                groups: group(ordered, duplicateIDs: duplicateIDs)
            )
        }

        let cluster = candidates.filter {
            $0.playlistID == anchor.playlistID || isEdition($0, of: anchor)
        }
        let clusterIDs = Set(cluster.map(\.playlistID))
        let independent = candidates.filter { !clusterIDs.contains($0.playlistID) }

        guard independent.allSatisfy({ $0.durationSeconds * 2 < anchor.durationSeconds }) else {
            return .collection(
                name: name,
                groups: group(ordered, duplicateIDs: duplicateIDs)
            )
        }

        let main = cluster.first(where: \.isMain) ?? anchor
        let editions = cluster.filter { $0.playlistID != main.playlistID }
        let versionNames = distinctNames(
            ([main] + editions).map {
                ($0, versionName(for: $0, discName: name,
                                 hasEditions: !editions.isEmpty))
            },
            duplicateSuffix: String(localized: "Version")
        )
        let presentedMain = presented(versionNames[0].0, name: versionNames[0].1, isMain: true)
        let presentedEditions = versionNames.dropFirst().map { presented($0.0, name: $0.1) }
        let editionIDs = Set(editions.map(\.playlistID))
        let additional = ordered.filter {
            $0.playlistID != main.playlistID &&
                !editionIDs.contains($0.playlistID)
        }

        return .feature(
            name: name,
            main: presentedMain,
            editions: presentedEditions,
            additional: additionalGroup(additional)
        )
    }
}

private extension BluRayDiscContent {
    static func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    static func discName(authored: String?, source: String) -> String {
        if let authored = cleaned(authored) { return authored }
        var source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.lowercased().hasSuffix(".iso") { source.removeLast(4) }
        return source.isEmpty ? String(localized: "Blu-ray disc") : source
    }

    static func titlePrecedes(_ lhs: BluRayDiscTitle, _ rhs: BluRayDiscTitle) -> Bool {
        if lhs.durationSeconds != rhs.durationSeconds {
            return lhs.durationSeconds > rhs.durationSeconds
        }
        if lhs.clips.count != rhs.clips.count {
            return lhs.clips.count < rhs.clips.count
        }
        let leftRoute = routeKey(lhs)
        let rightRoute = routeKey(rhs)
        if leftRoute != rightRoute { return leftRoute < rightRoute }
        return lhs.playlistID.rawValue < rhs.playlistID.rawValue
    }

    static func routeKey(_ title: BluRayDiscTitle) -> String {
        title.clips.map { clip in
            let video = clip.streams.first { $0.kind == .video }
            return [
                clip.clipID,
                String(clip.startTimeSeconds.bitPattern),
                String(clip.inTimeSeconds.bitPattern),
                String(clip.outTimeSeconds.bitPattern),
                String(video?.pid ?? 0),
                String(video?.codingType ?? 0)
            ].joined(separator: ":")
        }.joined(separator: "|")
    }

    static func duplicateRouteIDs(in titles: [BluRayDiscTitle]) -> Set<BluRayPlaylistID> {
        var representatives: [BluRayDiscTitle] = []
        var duplicates: Set<BluRayPlaylistID> = []
        for title in titles {
            guard let index = representatives.firstIndex(where: {
                sameVideoRoute(title, $0)
            }) else {
                representatives.append(title)
                continue
            }
            if title.isMain && !representatives[index].isMain {
                duplicates.insert(representatives[index].playlistID)
                representatives[index] = title
            } else {
                duplicates.insert(title.playlistID)
            }
        }
        return duplicates
    }

    static func isEdition(_ title: BluRayDiscTitle, of anchor: BluRayDiscTitle) -> Bool {
        guard !title.clips.isEmpty, !anchor.clips.isEmpty,
              title.durationSeconds > 0, anchor.durationSeconds > 0 else { return false }
        let (left, right) = atomized(title.clips, anchor.clips)
        guard left != right else { return false }
        let shared = orderedSharedTicks(left, right)
        return shared > ticks(title.durationSeconds) / 2 &&
            shared > ticks(anchor.durationSeconds) / 2
    }

    static func sameVideoRoute(_ lhs: BluRayDiscTitle, _ rhs: BluRayDiscTitle) -> Bool {
        guard !lhs.clips.isEmpty, !rhs.clips.isEmpty,
              !Set(lhs.clips.map(\.clipID)).isDisjoint(with: Set(rhs.clips.map(\.clipID)))
        else { return false }
        let (left, right) = atomized(lhs.clips, rhs.clips)
        return !left.isEmpty && left == right
    }

    struct ClipKey: Hashable {
        let id: String
        let videoPID: UInt16?
        let videoCodingType: UInt8?
    }

    struct Atom: Equatable {
        let key: ClipKey
        let lower: Int64
        let upper: Int64

        var duration: Int64 { upper - lower }
    }

    static func ticks(_ seconds: Double) -> Int64 {
        Int64((seconds * 90_000).rounded())
    }

    static func clipKey(_ clip: BluRayClip) -> ClipKey {
        let video = clip.streams.first { $0.kind == .video }
        return ClipKey(
            id: clip.clipID,
            videoPID: video?.pid,
            videoCodingType: video?.codingType
        )
    }

    static func atomized(
        _ lhs: [BluRayClip],
        _ rhs: [BluRayClip]
    ) -> ([Atom], [Atom]) {
        var boundaries: [ClipKey: Set<Int64>] = [:]
        for clip in lhs + rhs {
            let key = clipKey(clip)
            boundaries[key, default: []].insert(ticks(clip.inTimeSeconds))
            boundaries[key, default: []].insert(ticks(clip.outTimeSeconds))
        }
        let sorted = boundaries.mapValues { $0.sorted() }

        func split(_ clips: [BluRayClip]) -> [Atom] {
            clips.flatMap { clip -> [Atom] in
                let key = clipKey(clip)
                let lower = ticks(clip.inTimeSeconds)
                let upper = ticks(clip.outTimeSeconds)
                guard let points = sorted[key], lower < upper else { return [] }
                var atoms: [Atom] = []
                for index in 0..<(points.count - 1) {
                    let start = points[index]
                    let end = points[index + 1]
                    if lower <= start && end <= upper {
                        atoms.append(Atom(key: key, lower: start, upper: end))
                    }
                }
                return atoms
            }
        }

        return (split(lhs), split(rhs))
    }

    static func orderedSharedTicks(_ lhs: [Atom], _ rhs: [Atom]) -> Int64 {
        var previous = Array(repeating: Int64(0), count: rhs.count + 1)
        for left in lhs {
            var current = Array(repeating: Int64(0), count: rhs.count + 1)
            for (index, right) in rhs.enumerated() {
                let overlap = left == right ? left.duration : 0
                let sum = previous[index].addingReportingOverflow(overlap)
                current[index + 1] = max(
                    max(previous[index + 1], current[index]),
                    sum.overflow ? Int64.max : sum.partialValue
                )
            }
            previous = current
        }
        return previous[rhs.count]
    }

    static func kind(for title: BluRayDiscTitle) -> BluRayContentGroupKind {
        if title.clips.allSatisfy({ $0.stillMode != 0 }) && !title.clips.isEmpty {
            return .stillImages
        }
        if title.clips.allSatisfy({ !$0.streams.contains(where: { $0.kind == .video }) }) {
            return .additional
        }
        if title.clips.count > 1 { return .sequences }
        return .videos
    }

    static func group(
        _ titles: [BluRayDiscTitle],
        duplicateIDs: Set<BluRayPlaylistID>
    ) -> [BluRayContentGroup] {
        BluRayContentGroupKind.allCases.compactMap { kind in
            let members = titles.filter {
                (duplicateIDs.contains($0.playlistID)
                    ? .additional
                    : self.kind(for: $0)) == kind
            }
            guard !members.isEmpty else { return nil }
            let names = distinctNames(members.map {
                ($0, cleaned($0.optionalName) ?? genericName(for: $0, kind: kind))
            }, duplicateSuffix: String(localized: "Item"))
            return BluRayContentGroup(
                kind: kind,
                titles: names.map { presented($0.0, name: $0.1) }
            )
        }
    }

    static func additionalGroup(_ titles: [BluRayDiscTitle]) -> [BluRayContentGroup] {
        guard !titles.isEmpty else { return [] }
        let names = distinctNames(titles.map {
            ($0, cleaned($0.optionalName) ?? genericName(for: $0, kind: kind(for: $0)))
        }, duplicateSuffix: String(localized: "Item"))
        return [BluRayContentGroup(
            kind: .additional,
            titles: names.map { presented($0.0, name: $0.1) }
        )]
    }

    static func presented(
        _ title: BluRayDiscTitle,
        name: String,
        isMain: Bool = false
    ) -> BluRayPresentedTitle {
        BluRayPresentedTitle(
            playlistID: title.playlistID,
            displayName: name,
            durationSeconds: title.durationSeconds,
            isMain: isMain
        )
    }

    static func versionName(
        for title: BluRayDiscTitle,
        discName: String,
        hasEditions: Bool
    ) -> String {
        let base = cleaned(title.optionalName) ?? discName
        return hasEditions ? "\(base) · \(durationLabel(title.durationSeconds))" : base
    }

    static func genericName(
        for title: BluRayDiscTitle,
        kind: BluRayContentGroupKind
    ) -> String {
        let video = title.clips.lazy.flatMap(\.streams).first { $0.kind == .video }
        let format = video.map(videoDescription) ?? String(localized: "Format unknown")
        return "\(kind.displayName) · \(durationLabel(title.durationSeconds)) · \(format)"
    }

    static func videoDescription(_ stream: BluRayStream) -> String {
        let codec = switch stream.codingType {
        case 2: "MPEG-2"
        case 27: "H.264"
        case 36: "HEVC"
        case 234: "VC-1"
        default: String(localized: "Video format \(stream.codingType)")
        }
        let picture = switch stream.format {
        case 1: "480i"
        case 2: "576i"
        case 3: "480p"
        case 4: "1080i"
        case 5: "720p"
        case 6: "1080p"
        case 7: "576p"
        case 8: "2160p"
        default: ""
        }
        return picture.isEmpty ? codec : "\(codec) \(picture)"
    }

    static func durationLabel(_ seconds: Double) -> String {
        if seconds > 0 && seconds < 1 {
            return String(format: "%.3fs", seconds)
        }
        let whole = Int(seconds.rounded())
        let hours = whole / 3_600
        let minutes = (whole % 3_600) / 60
        let remaining = whole % 60
        if hours > 0 { return String(format: "%dh %02dm %02ds", hours, minutes, remaining) }
        if minutes > 0 { return String(format: "%dm %02ds", minutes, remaining) }
        return String(format: "%ds", remaining)
    }

    static func distinctNames(
        _ pairs: [(BluRayDiscTitle, String)],
        duplicateSuffix: String
    ) -> [(BluRayDiscTitle, String)] {
        let counts = Dictionary(pairs.map { ($0.1, 1) }, uniquingKeysWith: +)
        var indices: [String: Int] = [:]
        var result: [(BluRayDiscTitle, String)] = []
        for (title, base) in pairs {
            indices[base, default: 0] += 1
            let name = counts[base] == 1
                ? base
                : "\(base) · \(duplicateSuffix) \(indices[base, default: 0])"
            result.append((title, name))
        }
        return result
    }
}
