import CryptoKit
import Foundation

public nonisolated enum MediaSeriesName: Equatable, Sendable {
    case series(String)
    case episodeOnly

    public static func parse(fileName: String) -> MediaSeriesName? {
        let base = (fileName as NSString).deletingPathExtension
        let value = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false,
              let marker = markerStart(in: value) else { return nil }
        let stem = normalizedStem(String(value[value.startIndex..<marker]))
        return stem.isEmpty ? .episodeOnly : .series(stem)
    }

    private static let markerPatterns = [
        #"[sS]\d{1,2}[\s._-]?[eE]\d{1,3}"#,
        #"(?<![0-9])\d{1,2}[xX]\d{2,3}(?![0-9])"#,
        #"第\s*\d{1,4}\s*[集话話季]"#,
        #"(?:^|[\s._\-\[\(（【])[eE][pP]?[\s.]?\d{1,4}(?=[\s._\-\]\)）】]|$)"#,
        #"[\[\(（【]\s*\d{1,3}\s*[\]\)）】]"#,
        #"[\s._-]\d{1,3}(?=[\s._-]|$)"#,
        #"^\d{1,3}(?=[\s._-]|$)"#
    ]

    private static func markerStart(in value: String) -> String.Index? {
        var earliest: String.Index?
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        for pattern in markerPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: value, range: range),
                  let matched = Range(match.range, in: value) else { continue }
            if let current = earliest {
                if matched.lowerBound < current { earliest = matched.lowerBound }
            } else {
                earliest = matched.lowerBound
            }
        }
        return earliest
    }

    private static func normalizedStem(_ raw: String) -> String {
        let decorations = CharacterSet(charactersIn: " \t._-–—~+")
        var value = raw.trimmingCharacters(in: decorations)
        while let first = value.first, "[([（【".contains(first) {
            guard let close = value.firstIndex(where: { "])）】".contains($0) }) else { break }
            let rest = String(value[value.index(after: close)...]).trimmingCharacters(in: decorations)
            if rest.isEmpty { break }
            value = rest
        }
        return value.lowercased()
            .split(whereSeparator: {
                $0.isWhitespace || $0 == "." || $0 == "_" || $0 == "-"
            })
            .joined(separator: " ")
    }
}

public nonisolated struct TrackPreferenceScope: Codable, Hashable, Sendable {
    public let storageKey: String

    private init(storageKey: String) {
        self.storageKey = storageKey
    }

    public static func mediaServer(
        provider: String,
        serverID: String,
        seriesID: String
    ) -> Self {
        make(scope: "series", components: [provider, serverID, seriesID])
    }

    public static func file(
        sourceKey: String,
        directoryPath: String,
        fileName: String,
        itemIdentity: MediaIdentity?
    ) -> Self? {
        let directory = normalizedDirectory(directoryPath)
        switch MediaSeriesName.parse(fileName: fileName) {
        case .some(.series(let stem)) where directory.isEmpty == false:
            return make(
                scope: "directory-series",
                components: [sourceKey, directory, stem]
            )
        case .some(.episodeOnly) where directory.isEmpty == false:
            return make(scope: "directory", components: [sourceKey, directory])
        default:
            return itemIdentity.map { item($0) }
        }
    }

    public static func item(_ identity: MediaIdentity) -> Self {
        make(scope: "item", components: [identity.storageKey])
    }

    private static func normalizedDirectory(_ path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value == "/" ? "" : value
    }

    private static func make(scope: String, components: [String]) -> Self {
        let canonical = ([scope] + components).joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return Self(storageKey: digest.map { String(format: "%02x", $0) }.joined())
    }
}
