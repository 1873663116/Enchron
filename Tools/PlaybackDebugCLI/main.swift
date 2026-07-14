import Foundation

private let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    fputs("usage: PlaybackDebugCLI snapshot|play|pause|close|reopen|route <route>|seek <seconds>|rate <value>\n", stderr)
    exit(2)
}

let monotonicNanoseconds = DispatchTime.now().uptimeNanoseconds
let commandID = String(
    format: "%020llu-%@",
    monotonicNanoseconds,
    UUID().uuidString
)
var envelope: [String: Any] = [
    "commandID": commandID,
    "createdAt": ISO8601DateFormatter().string(from: Date()),
]
switch command {
case "snapshot", "play", "pause", "close", "reopen":
    envelope["kind"] = command
case "route":
    guard arguments.count == 2 else { exit(2) }
    envelope["kind"] = "route"
    envelope["route"] = arguments[1]
case "seek", "reopen-at":
    guard arguments.count == 2, let seconds = Double(arguments[1]) else { exit(2) }
    envelope["kind"] = "seek"
    envelope["seconds"] = seconds
case "rate":
    guard arguments.count == 2, let rate = Float(arguments[1]), rate >= 0 else { exit(2) }
    envelope["kind"] = "rate"
    envelope["rate"] = rate
default:
    fputs("unknown command: \(command)\n", stderr)
    exit(2)
}

let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("playbackcore-live-debug", isDirectory: true)
let commandsURL = root.appendingPathComponent("commands", isDirectory: true)
let acknowledgementsURL = root.appendingPathComponent("acknowledgements", isDirectory: true)
try FileManager.default.createDirectory(at: commandsURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: acknowledgementsURL, withIntermediateDirectories: true)

let commandURL = commandsURL.appendingPathComponent("\(commandID).json")
let acknowledgementURL = acknowledgementsURL.appendingPathComponent("\(commandID).json")
let data = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
try data.write(to: commandURL, options: .atomic)

let deadline = Date().addingTimeInterval(15)
while Date() < deadline {
    if let acknowledgement = try? Data(contentsOf: acknowledgementURL),
       let text = String(data: acknowledgement, encoding: .utf8) {
        print(text)
        exit(text.contains("\"status\" : \"completed\"") ? 0 : 1)
    }
    Thread.sleep(forTimeInterval: 0.1)
}

fputs("command timed out: \(commandID)\n", stderr)
exit(1)
