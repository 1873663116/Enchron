import Foundation

enum PlaybackDebugCommand {
    case snapshot
    case play
    case pause
    case close
    case reopen
    case route(PlaybackRoute)
    case seek(Double)
    case rate(Float)
}

@MainActor
final class PlaybackDebugCommandBridge {
    private struct Envelope: Decodable {
        var commandID: String
        var kind: String
        var route: String?
        var seconds: Double?
        var rate: Float?
    }

    private let handler: (PlaybackDebugCommand) async throws -> Void
    private let commandsURL: URL
    private let acknowledgementsURL: URL
    private var task: Task<Void, Never>?
    private var inFlightCommandIDs: Set<String> = []

    init(handler: @escaping (PlaybackDebugCommand) async throws -> Void) {
        self.handler = handler
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("playbackcore-live-debug", isDirectory: true)
        commandsURL = root.appendingPathComponent("commands", isDirectory: true)
        acknowledgementsURL = root.appendingPathComponent("acknowledgements", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: commandsURL,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: acknowledgementsURL,
            withIntermediateDirectories: true
        )
        task = Task { [weak self] in
            await self?.receiveCommands()
        }
    }

    deinit {
        task?.cancel()
    }

    private func receiveCommands() async {
        while !Task.isCancelled {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: commandsURL,
                includingPropertiesForKeys: nil
            ))?.filter { $0.pathExtension == "json" }.sorted {
                $0.lastPathComponent < $1.lastPathComponent
            } ?? []

            for file in files {
                guard !Task.isCancelled else { return }
                let commandID = file.deletingPathExtension().lastPathComponent
                guard !inFlightCommandIDs.contains(commandID) else { continue }
                if isSeekCommand(file) {
                    inFlightCommandIDs.insert(commandID)
                    Task { [weak self] in
                        guard let self else { return }
                        await self.receive(file)
                        self.inFlightCommandIDs.remove(commandID)
                    }
                } else if inFlightCommandIDs.isEmpty {
                    await receive(file)
                } else {
                    break
                }
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func isSeekCommand(_ file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return false
        }
        return envelope.kind == "seek"
    }

    private func receive(_ file: URL) async {
        do {
            let envelope = try JSONDecoder().decode(
                Envelope.self,
                from: Data(contentsOf: file)
            )
            guard let command = command(from: envelope) else {
                try writeAcknowledgement(
                    commandID: envelope.commandID,
                    status: "rejected",
                    message: "invalidPayload"
                )
                try? FileManager.default.removeItem(at: file)
                return
            }
            try await handler(command)
            try writeAcknowledgement(
                commandID: envelope.commandID,
                status: "completed",
                message: nil
            )
            try FileManager.default.removeItem(at: file)
        } catch {
            let commandID = file.deletingPathExtension().lastPathComponent
            try? writeAcknowledgement(
                commandID: commandID,
                status: "failed",
                message: error.localizedDescription
            )
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func command(from envelope: Envelope) -> PlaybackDebugCommand? {
        switch envelope.kind {
        case "snapshot": .snapshot
        case "play": .play
        case "pause": .pause
        case "close": .close
        case "reopen": .reopen
        case "route":
            envelope.route.flatMap(PlaybackRoute.init(rawValue:)).map(PlaybackDebugCommand.route)
        case "seek":
            envelope.seconds.map(PlaybackDebugCommand.seek)
        case "rate":
            envelope.rate.map(PlaybackDebugCommand.rate)
        default: nil
        }
    }

    private func writeAcknowledgement(
        commandID: String,
        status: String,
        message: String?
    ) throws {
        var acknowledgement: [String: Any] = [
            "commandID": commandID,
            "status": status,
            "completedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        if let message { acknowledgement["message"] = message }
        let data = try JSONSerialization.data(
            withJSONObject: acknowledgement,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(
            to: acknowledgementsURL.appendingPathComponent("\(commandID).json"),
            options: .atomic
        )
    }
}
