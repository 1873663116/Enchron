import BluRayDisc
import BluRayDiscBridge
import Foundation

@main
struct BluRayDiscProbe {
    private struct ProbeStream: Codable {
        let pid: UInt16
        let codingType: UInt8
        let kind: String
        let language: String?
    }

    private struct ProbeClip: Codable {
        let clipID: String
        let startTime90k: Int64
        let inTime90k: Int64
        let outTime90k: Int64
        let byteStart: UInt64
        let byteEnd: UInt64
        let streams: [ProbeStream]
    }

    private struct ProbeTitle: Codable {
        let playlistID: UInt32
        let duration90k: Int64
        let isMain: Bool
        let optionalName: String?
        let clips: [ProbeClip]
    }

    private struct ProbeCatalog: Codable {
        let schema: String
        let titles: [ProbeTitle]
    }

    private static func ticks(_ seconds: Double) -> Int64 {
        Int64((seconds * 90_000).rounded())
    }

    static func main() async throws {
        let arguments = CommandLine.arguments
        let json = arguments.count >= 2 && arguments[1] == "--json"
        let pathIndex = json ? 2 : 1
        guard arguments.count > pathIndex else {
            fputs("Usage: BluRayDiscProbe [--json] <local ISO or BDMV path> [playlist ID]\n", stderr)
            exit(2)
        }
        let url = URL(fileURLWithPath: arguments[pathIndex])
        let catalog = try BluRayDisc.catalog(at: url)
        if json {
            let document = ProbeCatalog(schema: "enchron.bluray.probe/v1", titles: catalog.titles.map { title in
                ProbeTitle(
                    playlistID: title.playlistID.rawValue,
                    duration90k: ticks(title.durationSeconds),
                    isMain: title.isMain,
                    optionalName: title.optionalName,
                    clips: title.clips.map { clip in
                        ProbeClip(
                            clipID: clip.clipID,
                            startTime90k: ticks(clip.startTimeSeconds),
                            inTime90k: ticks(clip.inTimeSeconds),
                            outTime90k: ticks(clip.outTimeSeconds),
                            byteStart: clip.byteStart,
                            byteEnd: clip.byteEnd,
                            streams: clip.streams.map { stream in
                                ProbeStream(pid: stream.pid, codingType: stream.codingType,
                                    kind: String(describing: stream.kind), language: stream.language)
                            }
                        )
                    }
                )
            })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(document)
            data.append(0x0a)
            FileHandle.standardOutput.write(data)
            return
        }
        for title in catalog.titles {
            let clips = title.clips.map {
                "\($0.clipID)[\($0.inTimeSeconds),\($0.outTimeSeconds))@\($0.startTimeSeconds) bytes=\($0.byteStart)..<\($0.byteEnd)"
            }.joined(separator: ",")
            print("playlist=\(title.playlistID.rawValue) duration=\(title.durationSeconds) main=\(title.isMain) clips=\(clips)")
        }
        guard arguments.count > pathIndex + 1,
              let rawID = UInt32(arguments[pathIndex + 1]) else { return }
        let reader = try await BluRayDisc.open(source: .url(url),
                                               playlistID: BluRayPlaylistID(rawValue: rawID))
        guard let handle = reader.takeNativeHandle() else {
            throw BluRayDiscError.io("Reader handle was already transferred.")
        }
        defer { PBBlurayClose(handle) }
        var bytes = [UInt8](repeating: 0, count: 6 * 192)
        let count = PBBlurayRead(handle, &bytes, Int32(bytes.count))
        guard count >= 0 else { throw BluRayDiscError.io("Title read failed.") }
        let prefix = bytes.prefix(Int(count)).map { String(format: "%02x", $0) }.joined()
        print("read=\(count) size=\(PBBluraySize(handle)) duration90k=\(PBBlurayDuration(handle)) firstBytes=\(prefix)")
    }
}
