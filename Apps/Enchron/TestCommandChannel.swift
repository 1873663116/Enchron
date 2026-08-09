import Foundation
import MediaLibrary

@MainActor
final class TestCommandChannel {
    private struct Request: Decodable {
        let id: String
        let verb: String
        let args: [String: String]
    }

    private struct Response: Encodable {
        let id: String
        let ok: Bool
        let detail: String?
        let payload: [String]?
    }

    private struct CommandError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    private let mediaLibrary: MediaLibraryViewModel
    private let appModel: AppModel
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let commandURL: URL
    private let responsesURL: URL
    private let inboxURL: URL
    private var pollingTask: Task<Void, Never>?

    init(
        mediaLibrary: MediaLibraryViewModel,
        appModel: AppModel,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) throws {
        self.mediaLibrary = mediaLibrary
        self.appModel = appModel
        self.fileManager = fileManager
        self.defaults = defaults

        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        commandURL = documentsURL.appending(path: "test-command.json")
        responsesURL = documentsURL.appending(
            path: "test-responses",
            directoryHint: .isDirectory
        )
        inboxURL = documentsURL.appending(
            path: "TestMediaInbox",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: responsesURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: inboxURL,
            withIntermediateDirectories: true
        )
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while Task.isCancelled == false {
                self?.processRequestIfPresent()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func processRequestIfPresent() {
        guard fileManager.fileExists(atPath: commandURL.path) else { return }

        do {
            let request = try JSONDecoder().decode(
                Request.self,
                from: Data(contentsOf: commandURL)
            )
            let responseURL = responsesURL.appending(path: "\(request.id).json")
            if fileManager.fileExists(atPath: responseURL.path) {
                try fileManager.removeItem(at: commandURL)
                return
            }

            AppModel.recordProbe("testcmd \(request.verb) begin")
            let response: Response
            do {
                response = try execute(request)
            } catch {
                response = Response(
                    id: request.id,
                    ok: false,
                    detail: error.localizedDescription,
                    payload: nil
                )
            }

            let data = try JSONEncoder().encode(response)
            try data.write(to: responseURL, options: .atomic)
            AppModel.recordProbe(
                "testcmd \(request.verb) \(response.ok ? "ok" : "failed")"
            )
            try fileManager.removeItem(at: commandURL)
        } catch {
            AppModel.recordProbe(
                "testcmd channel failed error=\(error.localizedDescription)"
            )
        }
    }

    private func execute(_ request: Request) throws -> Response {
        switch request.verb {
        case "ping":
            return Response(id: request.id, ok: true, detail: nil, payload: nil)
        case "toggleControls":
            appModel.toggleControlsFromPlaybackSurface()
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [String(appModel.showControls)]
            )
        case "resetState":
            // TestMediaInbox is harness-owned staging, not app state; clearing
            // it here would force a re-push of every media file per cell.
            let keys = defaults.dictionaryRepresentation().keys.filter {
                $0.hasPrefix("enchron.")
            }
            for key in keys {
                defaults.removeObject(forKey: key)
            }
            return Response(
                id: request.id,
                ok: true,
                detail: "Deleted \(keys.count) enchron.* defaults keys.",
                payload: nil
            )
        case "importMedia":
            guard let fileName = request.args["file"],
                  fileName.isEmpty == false,
                  fileName != ".",
                  fileName != "..",
                  (fileName as NSString).lastPathComponent == fileName else {
                throw CommandError(
                    message: "importMedia requires a direct TestMediaInbox file name."
                )
            }
            let fileURL = inboxURL.appending(
                path: fileName,
                directoryHint: .notDirectory
            )
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: fileURL.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue == false else {
                throw CommandError(
                    message: "TestMediaInbox does not contain \(fileName)."
                )
            }

            let referenceIDsBeforeImport = Set(allReferences.map(\.id))
            mediaLibrary.addFiles([fileURL])
            if let detail = mediaLibrary.lastErrorMessage {
                throw CommandError(message: detail)
            }
            guard allReferences.contains(where: {
                referenceIDsBeforeImport.contains($0.id) == false
            }) else {
                throw CommandError(
                    message: "The production media import pipeline did not add \(fileName)."
                )
            }
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: allReferenceNames
            )
        case "listLibrary":
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: allReferenceNames
            )
        default:
            throw CommandError(
                message: "Unknown app command verb: \(request.verb)."
            )
        }
    }

    private var allReferences: [FileBrowsingDomain.MediaReference] {
        let library = mediaLibrary.library
        return library.references(in: nil) + mediaLibrary.allFolders.flatMap {
            library.references(in: $0.id)
        }
    }

    private var allReferenceNames: [String] {
        allReferences.map(\.name)
    }
}

@MainActor
private enum TestCommandChannelBootstrap {
    static var activeChannel: TestCommandChannel?

    static func installIfEnabled(
        environment: [String: String],
        application: EnchronApplication
    ) {
        guard environment["ENCHRON_TEST_CHANNEL"] == "1" else { return }
        do {
            let channel = try TestCommandChannel(
                mediaLibrary: application.mediaLibraryViewModel,
                appModel: application.appModel
            )
            activeChannel = channel
            channel.start()
        } catch {
            AppModel.recordProbe(
                "testcmd channel failed error=\(error.localizedDescription)"
            )
        }
    }
}

extension EnchronApplication {
    convenience init() {
        let environment = ProcessInfo.processInfo.environment
        self.init(environment: environment)
        TestCommandChannelBootstrap.installIfEnabled(
            environment: environment,
            application: self
        )
    }
}
