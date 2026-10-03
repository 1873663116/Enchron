import BluRayDisc
import Foundation
import MediaLibrary
import Testing

@main
struct BluRayContentLogicProbe {
    static func main() async throws {
        if CommandLine.arguments.contains("--testing-library") {
            await Testing.__swiftPMEntryPoint() as Never
        }
        guard CommandLine.arguments.count > 1 else {
            throw BluRayDiscError.unsupported("Supply at least one disc path.")
        }
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            let catalog = try BluRayDisc.catalog(at: url)
            let source = url.lastPathComponent.caseInsensitiveCompare("BDMV") == .orderedSame
                ? url.deletingLastPathComponent().lastPathComponent
                : (url.lastPathComponent as NSString).deletingPathExtension
            let content = try BluRayDiscContent.project(catalog, sourceName: source)
            let kind: String = switch content {
            case .feature: "feature"
            case .collection: "collection"
            }
            let output: [String: Any] = [
                "schema": "enchron.bluray.content/v1",
                "name": content.name,
                "kind": kind,
                "authoredPlaylistCount": catalog.titles.count,
                "primaryTitles": content.primaryTitles.map(describe),
                "groups": content.groups.map {
                    ["kind": $0.kind.rawValue, "name": $0.kind.displayName,
                     "titles": $0.titles.map(describe)] as [String: Any]
                }
            ]
            var encoded = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
            encoded.append(0x0a)
            FileHandle.standardOutput.write(encoded)
        }
    }

    private static func describe(_ title: BluRayPresentedTitle) -> [String: Any] {
        ["name": title.displayName, "playlistID": title.playlistID.rawValue,
         "durationSeconds": title.durationSeconds, "isMain": title.isMain]
    }
}
