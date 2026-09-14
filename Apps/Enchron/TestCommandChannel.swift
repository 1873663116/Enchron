#if DEBUG
import DesignSystem
import CryptoKit
import Emby
import Foundation
import MediaLibrary
import MediaSource
import PlaybackCore
import Playback
#if os(visionOS)
import UIKit
#endif

struct LibraryEvidenceSnapshot: Encodable, Equatable {
    struct Folder: Encodable, Equatable {
        let id: String
        let parentID: String?
        let name: String
    }

    struct Reference: Encodable, Equatable {
        let id: String
        let folderID: String?
        let name: String
        let locatorKind: String
        let sourceIdentity: String
        let sourcePath: String
        let sourceExists: Bool?
        let sourceDigest: String?
        let sizeInBytes: Int64
    }

    struct StagedFile: Encodable, Equatable {
        let name: String
        let sizeInBytes: Int64
        let digest: String
    }

    let folders: [Folder]
    let references: [Reference]
    let stagedFiles: [StagedFile]

    init(
        library: FileBrowsingDomain.MediaLibrary,
        folders sourceFolders: [FileBrowsingDomain.LibraryFolder],
        inboxURL: URL,
        fileManager: FileManager
    ) {
        folders = sourceFolders
            .map {
                Folder(
                    id: $0.id.uuidString.lowercased(),
                    parentID: $0.parentID?.uuidString.lowercased(),
                    name: $0.name
                )
            }
            .sorted { $0.id < $1.id }

        let locations: [(UUID?, FileBrowsingDomain.MediaReference)] =
            library.references(in: nil).map { (nil, $0) }
            + sourceFolders.flatMap { folder in
                library.references(in: folder.id).map { (folder.id, $0) }
            }
        references = locations
            .map { folderID, reference in
                Self.reference(
                    reference,
                    folderID: folderID,
                    fileManager: fileManager
                )
            }
            .sorted { $0.id < $1.id }

        let candidates = (try? fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        stagedFiles = candidates.compactMap { url in
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ), values.isRegularFile == true,
                  let digest = Self.fileDigest(url) else { return nil }
            return StagedFile(
                name: url.lastPathComponent,
                sizeInBytes: Int64(values.fileSize ?? 0),
                digest: digest
            )
        }
        .sorted { $0.name < $1.name }
    }

    private static func reference(
        _ reference: FileBrowsingDomain.MediaReference,
        folderID: UUID?,
        fileManager: FileManager
    ) -> Reference {
        switch reference.locator {
        case .sourceItem(let dataSourceID, let path):
            let identity = digest(
                Data("sourceItem\u{0}\(dataSourceID.uuidString.lowercased())\u{0}\(path)".utf8)
            )
            return Reference(
                id: reference.id.uuidString.lowercased(),
                folderID: folderID?.uuidString.lowercased(),
                name: reference.name,
                locatorKind: "sourceItem",
                sourceIdentity: identity,
                sourcePath: path,
                sourceExists: nil,
                sourceDigest: nil,
                sizeInBytes: reference.sizeInBytes
            )
        case .file(let bookmark, let relativePath):
            let identity = digest(
                bookmark + Data([0]) + Data(relativePath.utf8)
            )
            var stale = false
            let root = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            let source = stale ? nil : root.map {
                relativePath.isEmpty
                    ? $0
                    : $0.appending(path: relativePath).standardizedFileURL
            }
            let accessStarted = source?.startAccessingSecurityScopedResource() == true
            defer {
                if accessStarted { source?.stopAccessingSecurityScopedResource() }
            }
            let exists = source.map { fileManager.fileExists(atPath: $0.path) }
            return Reference(
                id: reference.id.uuidString.lowercased(),
                folderID: folderID?.uuidString.lowercased(),
                name: reference.name,
                locatorKind: "file",
                sourceIdentity: identity,
                sourcePath: source?.path ?? "unresolved",
                sourceExists: exists,
                sourceDigest: source.flatMap(Self.fileDigest),
                sizeInBytes: reference.sizeInBytes
            )
        }
    }

    private static func fileDigest(_ url: URL) -> String? {
        guard let input = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? input.close() }
        var hasher = SHA256()
        do {
            while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
        } catch {
            return nil
        }
        return "sha256:" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func digest(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct ProductStateResetReceipt: Encodable, Equatable {
    static let schemaValue = "enchron.regression.product-state-reset@1"

    let schema: String
    let removedReferenceCount: Int
    let removedFolderCount: Int
    let removedManagedDefaultKeys: [String]
    let remainingReferenceCount: Int
    let remainingFolderCount: Int
    let remainingManagedDefaultKeys: [String]
    let createdFolderNames: [String]

    init(
        removedReferenceCount: Int,
        removedFolderCount: Int,
        removedManagedDefaultKeys: [String],
        remainingReferenceCount: Int,
        remainingFolderCount: Int,
        remainingManagedDefaultKeys: [String],
        createdFolderNames: [String]
    ) {
        self.schema = Self.schemaValue
        self.removedReferenceCount = removedReferenceCount
        self.removedFolderCount = removedFolderCount
        self.removedManagedDefaultKeys = removedManagedDefaultKeys.sorted()
        self.remainingReferenceCount = remainingReferenceCount
        self.remainingFolderCount = remainingFolderCount
        self.remainingManagedDefaultKeys = remainingManagedDefaultKeys.sorted()
        self.createdFolderNames = createdFolderNames.sorted()
    }

    static func managedDefaultKeys(in defaults: UserDefaults) -> [String] {
        defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("enchron.")
                || $0.hasPrefix("server-certificate-fingerprint.")
        }
        .sorted()
    }
}

struct TestMediaDirectorySource: Equatable {
    enum SourceError: LocalizedError {
        case invalidDirectoryName
        case invalidMediaFileName
        case invalidMemberFileName(String)
        case duplicateMemberFileName(String)
        case missingMediaFile
        case directoryConflictsWithMember
        case unavailableInbox
        case unavailableMember(String)
        case destinationIsNotDirectory

        var errorDescription: String? {
            switch self {
            case .invalidDirectoryName:
                return "The media directory name must be one direct TestMediaInbox child."
            case .invalidMediaFileName:
                return "The media file name must be one direct TestMediaInbox child."
            case .invalidMemberFileName(let name):
                return "The directory member is not one direct TestMediaInbox file: \(name)."
            case .duplicateMemberFileName(let name):
                return "The media directory contains a duplicate member name: \(name)."
            case .missingMediaFile:
                return "The media directory members must include the requested media file."
            case .directoryConflictsWithMember:
                return "The media directory name conflicts with one of its member files."
            case .unavailableInbox:
                return "TestMediaInbox is unavailable."
            case .unavailableMember(let name):
                return "TestMediaInbox does not contain the regular staged file \(name)."
            case .destinationIsNotDirectory:
                return "The requested TestMediaInbox directory name is occupied by a file."
            }
        }
    }

    let directoryName: String
    let mediaFileName: String
    let memberFileNames: [String]

    init(
        directoryName: String,
        mediaFileName: String,
        memberFileNames: [String]
    ) throws {
        guard Self.isDirectChildName(directoryName) else {
            throw SourceError.invalidDirectoryName
        }
        guard Self.isDirectChildName(mediaFileName) else {
            throw SourceError.invalidMediaFileName
        }
        var uniqueNames: Set<String> = []
        for name in memberFileNames {
            guard Self.isDirectChildName(name) else {
                throw SourceError.invalidMemberFileName(name)
            }
            guard uniqueNames.insert(name).inserted else {
                throw SourceError.duplicateMemberFileName(name)
            }
        }
        guard uniqueNames.contains(mediaFileName) else {
            throw SourceError.missingMediaFile
        }
        guard uniqueNames.contains(directoryName) == false else {
            throw SourceError.directoryConflictsWithMember
        }
        self.directoryName = directoryName
        self.mediaFileName = mediaFileName
        self.memberFileNames = uniqueNames.sorted()
    }

    func materialize(in inboxURL: URL, fileManager: FileManager) throws -> URL {
        let inbox = inboxURL.standardizedFileURL
        let inboxValues = try? inbox.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        guard inboxValues?.isDirectory == true,
              inboxValues?.isSymbolicLink != true else {
            throw SourceError.unavailableInbox
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        let members = try memberFileNames.map { name in
            let url = inbox.appending(path: name, directoryHint: .notDirectory)
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true,
                  values?.isSymbolicLink != true else {
                throw SourceError.unavailableMember(name)
            }
            return url
        }

        let stagingURL = inbox.appending(
            path: ".enchron-directory-import-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: stagingURL) }
        for memberURL in members {
            try fileManager.copyItem(
                at: memberURL,
                to: stagingURL.appending(
                    path: memberURL.lastPathComponent,
                    directoryHint: .notDirectory
                )
            )
        }

        let directoryURL = inbox.appending(
            path: directoryName,
            directoryHint: .isDirectory
        )
        var destinationIsDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: directoryURL.path,
            isDirectory: &destinationIsDirectory
        ) {
            guard destinationIsDirectory.boolValue else {
                throw SourceError.destinationIsNotDirectory
            }
            try fileManager.removeItem(at: directoryURL)
        }
        try fileManager.moveItem(at: stagingURL, to: directoryURL)
        return directoryURL
    }

    private static func isDirectChildName(_ value: String) -> Bool {
        value.isEmpty == false
            && value != "."
            && value != ".."
            && value.trimmingCharacters(in: .whitespacesAndNewlines) == value
            && (value as NSString).lastPathComponent == value
    }
}

struct DirectoryMediaImportReceipt: Encodable, Equatable {
    static let schemaValue = "enchron.regression.directory-media-import@1"

    enum ReceiptError: LocalizedError {
        case mismatchedReference
        case unresolvedBookmark
        case bookmarkRootIsNotDirectory
        case unavailableMember(String)

        var errorDescription: String? {
            switch self {
            case .mismatchedReference:
                return "The imported media reference does not identify the requested directory media."
            case .unresolvedBookmark:
                return "The imported media directory bookmark is unavailable."
            case .bookmarkRootIsNotDirectory:
                return "The imported bookmark does not resolve to a directory."
            case .unavailableMember(let name):
                return "The imported directory does not contain the regular member \(name)."
            }
        }
    }

    let schema: String
    let directoryName: String
    let mediaFileName: String
    let memberFileNames: [String]
    let referenceID: String
    let bookmarkRootPath: String
    let bookmarkRootIsDirectory: Bool
    let mediaRelativePath: String
    let mediaSourcePath: String

    init(
        source: TestMediaDirectorySource,
        reference: FileBrowsingDomain.MediaReference,
        fileManager: FileManager
    ) throws {
        guard reference.name == source.mediaFileName,
              case .file(let bookmark, let relativePath) = reference.locator,
              relativePath == source.mediaFileName,
              relativePath.isEmpty == false else {
            throw ReceiptError.mismatchedReference
        }

        var stale = false
        guard let resolvedRoot = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), stale == false else {
            throw ReceiptError.unresolvedBookmark
        }
        let root = resolvedRoot.standardizedFileURL
        let accessStarted = root.startAccessingSecurityScopedResource()
        defer { if accessStarted { root.stopAccessingSecurityScopedResource() } }
        let rootValues = try? root.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        guard rootValues?.isDirectory == true,
              rootValues?.isSymbolicLink != true else {
            throw ReceiptError.bookmarkRootIsNotDirectory
        }

        let memberKeys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        for name in source.memberFileNames {
            let member = root.appending(path: name, directoryHint: .notDirectory)
            let values = try? member.resourceValues(forKeys: memberKeys)
            guard values?.isRegularFile == true,
                  values?.isSymbolicLink != true else {
                throw ReceiptError.unavailableMember(name)
            }
        }

        schema = Self.schemaValue
        directoryName = source.directoryName
        mediaFileName = source.mediaFileName
        memberFileNames = source.memberFileNames
        referenceID = reference.id.uuidString.lowercased()
        bookmarkRootPath = root.path
        bookmarkRootIsDirectory = true
        mediaRelativePath = relativePath
        mediaSourcePath = root.appending(
            path: relativePath,
            directoryHint: .notDirectory
        ).standardizedFileURL.path
    }
}

#if DEBUG
nonisolated struct EmbyRuntimeIdentityCleanup {
    enum CleanupError: LocalizedError {
        case removalFailed

        var errorDescription: String? {
            "The staged Emby runtime identity could not be removed."
        }
    }

    private let fileURL: URL
    private let removeFile: (URL) throws -> Void

    init(fileURL: URL, fileManager: FileManager) {
        self.init(
            fileURL: fileURL,
            removeFile: { try fileManager.removeItem(at: $0) }
        )
    }

    init(
        fileURL: URL,
        removeFile: @escaping (URL) throws -> Void
    ) {
        self.fileURL = fileURL
        self.removeFile = removeFile
    }

    func perform<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        let outcome: Result<T, any Error>
        do {
            outcome = .success(try await operation())
        } catch {
            outcome = .failure(error)
        }

        do {
            try removeFile(fileURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
        } catch {
            throw CleanupError.removalFailed
        }
        return try outcome.get()
    }
}
#endif

@MainActor
final class TestCommandChannel {
    private struct Request: Decodable {
        let id: String
        let verb: String
        let args: [String: String]
    }

    private struct Response: Encodable {
        struct MenuItem: Encodable {
            let id: String
            let title: String
            let isSelected: Bool
        }

        let id: String
        let ok: Bool
        let detail: String?
        let payload: [String]?
        var menuItems: [MenuItem]?
        var librarySnapshot: LibraryEvidenceSnapshot?
        var productStateResetReceipt: ProductStateResetReceipt?
        var directoryMediaImportReceipt: DirectoryMediaImportReceipt?
        #if DEBUG
            var systemImportDeliverySnapshot: SystemImportDeliveryDiagnostics.Snapshot?
            var viewingStorageSnapshot: ViewingStorageDiagnosticSnapshot?
            var transitionTraceSnapshot: PlaybackSwitchStateSnapshot?
            var transitionTraceAnalysis: PlaybackSwitchStateAnalysis?
            var embySignInReceipt: EmbySignInReceipt?
        #endif

        #if DEBUG
        init(
            id: String,
            ok: Bool,
            detail: String?,
            payload: [String]?,
            menuItems: [MenuItem]? = nil,
            librarySnapshot: LibraryEvidenceSnapshot? = nil,
            productStateResetReceipt: ProductStateResetReceipt? = nil,
            directoryMediaImportReceipt: DirectoryMediaImportReceipt? = nil,
            systemImportDeliverySnapshot: SystemImportDeliveryDiagnostics.Snapshot? = nil,
            viewingStorageSnapshot: ViewingStorageDiagnosticSnapshot? = nil,
            transitionTraceSnapshot: PlaybackSwitchStateSnapshot? = nil,
            transitionTraceAnalysis: PlaybackSwitchStateAnalysis? = nil,
            embySignInReceipt: EmbySignInReceipt? = nil
        ) {
            self.id = id
            self.ok = ok
            self.detail = detail
            self.payload = payload
            self.menuItems = menuItems
            self.librarySnapshot = librarySnapshot
            self.productStateResetReceipt = productStateResetReceipt
            self.directoryMediaImportReceipt = directoryMediaImportReceipt
            self.systemImportDeliverySnapshot = systemImportDeliverySnapshot
            self.viewingStorageSnapshot = viewingStorageSnapshot
            self.transitionTraceSnapshot = transitionTraceSnapshot
            self.transitionTraceAnalysis = transitionTraceAnalysis
            self.embySignInReceipt = embySignInReceipt
        }
        #else
        init(
            id: String,
            ok: Bool,
            detail: String?,
            payload: [String]?,
            menuItems: [MenuItem]? = nil,
            librarySnapshot: LibraryEvidenceSnapshot? = nil,
            productStateResetReceipt: ProductStateResetReceipt? = nil,
            directoryMediaImportReceipt: DirectoryMediaImportReceipt? = nil
        ) {
            self.id = id
            self.ok = ok
            self.detail = detail
            self.payload = payload
            self.menuItems = menuItems
            self.librarySnapshot = librarySnapshot
            self.productStateResetReceipt = productStateResetReceipt
            self.directoryMediaImportReceipt = directoryMediaImportReceipt
        }
        #endif
    }

    private struct CommandError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    private let mediaLibrary: MediaLibraryViewModel
    private let mediaLibraryUIState: MediaLibraryUIState
    private let fileBrowser: FileBrowsingViewModel
    private let playbackSession: PlaybackSessionModel
    private let playbackRuntime: PlaybackRuntime
    private let playbackLauncher: PlaybackLaunchCoordinator
    private let settings: SettingsViewModel
    #if DEBUG
        private var playbackSwitchStateRing = PlaybackSwitchStateRing(capacity: 2_048)
    #endif
    private let embySession: EmbySessionViewModel
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let commandURL: URL
    private let commandsURL: URL
    private let responsesURL: URL
    private let responseSessionURL: URL
    private let inboxURL: URL
#if DEBUG
    private let embyRuntimeIdentityURL: URL
#endif
    private var pollingTask: Task<Void, Never>?

    init(
        mediaLibrary: MediaLibraryViewModel,
        mediaLibraryUIState: MediaLibraryUIState,
        fileBrowser: FileBrowsingViewModel,
        playbackSession: PlaybackSessionModel,
        playbackRuntime: PlaybackRuntime,
        playbackLauncher: PlaybackLaunchCoordinator,
        settings: SettingsViewModel,
        embySession: EmbySessionViewModel,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) throws {
        self.mediaLibrary = mediaLibrary
        self.mediaLibraryUIState = mediaLibraryUIState
        self.fileBrowser = fileBrowser
        self.playbackSession = playbackSession
        self.playbackRuntime = playbackRuntime
        self.playbackLauncher = playbackLauncher
        self.settings = settings
        self.embySession = embySession
        self.fileManager = fileManager
        self.defaults = defaults

        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        commandURL = documentsURL.appending(path: "test-command.json")
        commandsURL = documentsURL.appending(
            path: "test-commands",
            directoryHint: .isDirectory
        )
        responsesURL = documentsURL.appending(
            path: "test-responses",
            directoryHint: .isDirectory
        )
        responseSessionURL = documentsURL.appending(
            path: "test-response-session.txt"
        )
        inboxURL = documentsURL.appending(
            path: "TestMediaInbox",
            directoryHint: .isDirectory
        )
#if DEBUG
        let regressionURL = documentsURL.appending(
            path: "Regression",
            directoryHint: .isDirectory
        )
        embyRuntimeIdentityURL = regressionURL.appending(
            path: "emby-runtime-identity.json",
            directoryHint: .notDirectory
        )
#endif
        var inboxIsDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: inboxURL.path,
            isDirectory: &inboxIsDirectory
        ), inboxIsDirectory.boolValue == false {
            try fileManager.removeItem(at: inboxURL)
        }
        try fileManager.createDirectory(
            at: commandsURL,
            withIntermediateDirectories: true
        )
        for queuedCommandURL in try fileManager.contentsOfDirectory(
            at: commandsURL,
            includingPropertiesForKeys: nil
        ) where queuedCommandURL.pathExtension == "json" {
            try fileManager.removeItem(at: queuedCommandURL)
        }
        try fileManager.createDirectory(
            at: responsesURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: inboxURL,
            withIntermediateDirectories: true
        )
#if DEBUG
        var regressionIsDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: regressionURL.path,
            isDirectory: &regressionIsDirectory
        ), regressionIsDirectory.boolValue == false {
            try fileManager.removeItem(at: regressionURL)
        }
        try fileManager.createDirectory(
            at: regressionURL,
            withIntermediateDirectories: true
        )
#endif
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while Task.isCancelled == false {
                await self?.processRequestIfPresent()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    #if DEBUG
        func usePlaybackSwitchStateRing(_ ring: PlaybackSwitchStateRing) {
            playbackSwitchStateRing = ring
        }
    #endif

    private func processRequestIfPresent() async {
        do {
            guard let requestURL = try nextRequestURL() else { return }
            let request = try JSONDecoder().decode(
                Request.self,
                from: Data(contentsOf: requestURL)
            )
#if DEBUG
            try prepareEvidenceSession(for: request, requestURL: requestURL)
#endif
            let responseURL = responsesURL.appending(path: "\(request.id).json")
            if fileManager.fileExists(atPath: responseURL.path) {
                if requestURL == commandURL {
                    try fileManager.removeItem(at: requestURL)
                }
                return
            }

#if DEBUG
            if let evidenceSession = request.args["evidenceSession"],
               evidenceSession.isEmpty == false {
                SurfaceInputProbes.record(
                    "reachability evidence session=\(evidenceSession)"
                        + " command=\(request.id) verb=\(request.verb)",
                    retention: .evidenceSession(evidenceSession)
                )
            }
#endif
            SurfaceInputProbes.record(
                "testcmd \(request.verb) begin",
                retention: .evidence
            )
            let response: Response
            do {
                response = try await execute(request)
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
            SurfaceInputProbes.record(
                "testcmd \(request.verb) \(response.ok ? "ok" : "failed")",
                retention: .evidence
            )
            if requestURL == commandURL {
                try fileManager.removeItem(at: requestURL)
            }
        } catch {
            SurfaceInputProbes.record(
                "testcmd channel failed error=\(error.localizedDescription)",
                retention: .evidence
            )
        }
    }

    private func nextRequestURL() throws -> URL? {
        if fileManager.fileExists(atPath: commandURL.path) {
            return commandURL
        }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        return try fileManager.contentsOfDirectory(
            at: commandsURL,
            includingPropertiesForKeys: Array(keys)
        )
        .filter { requestURL in
            guard requestURL.pathExtension == "json" else { return false }
            let responseURL = responsesURL.appending(
                path: "\(requestURL.deletingPathExtension().lastPathComponent).json"
            )
            return fileManager.fileExists(atPath: responseURL.path) == false
        }
        .sorted { lhs, rhs in
            let lhsDate = try? lhs.resourceValues(forKeys: keys)
                .contentModificationDate
            let rhsDate = try? rhs.resourceValues(forKeys: keys)
                .contentModificationDate
            return (lhsDate ?? .distantPast) < (rhsDate ?? .distantPast)
        }
        .first
    }

#if DEBUG
    nonisolated private static func switchCounters(
        _ counters: MediaByteStreamDebugCounters?
    ) -> PlaybackSwitchByteStreamCounters? {
        counters.map {
            PlaybackSwitchByteStreamCounters(
                scope: $0.scope,
                acceptedConnectionCount: $0.acceptedConnectionCount,
                requestCount: $0.requestCount
            )
        }
    }

    private func prepareEvidenceSession(
        for request: Request,
        requestURL: URL
    ) throws {
        guard let evidenceSession = request.args["evidenceSession"],
              evidenceSession.isEmpty == false else { return }
        let currentSession = try? String(
            contentsOf: responseSessionURL,
            encoding: .utf8
        )
        guard currentSession != evidenceSession else { return }
        for responseURL in try fileManager.contentsOfDirectory(
            at: responsesURL,
            includingPropertiesForKeys: nil
        ) where responseURL.pathExtension == "json" {
            try fileManager.removeItem(at: responseURL)
        }
        for queuedCommandURL in try fileManager.contentsOfDirectory(
            at: commandsURL,
            includingPropertiesForKeys: nil
        ) where queuedCommandURL.pathExtension == "json"
            && queuedCommandURL != requestURL {
            try fileManager.removeItem(at: queuedCommandURL)
        }
        try evidenceSession.write(
            to: responseSessionURL,
            atomically: true,
            encoding: .utf8
        )
    }
#endif

    private func execute(_ request: Request) async throws -> Response {
        switch request.verb {
        case "ping":
            return Response(id: request.id, ok: true, detail: nil, payload: nil)
#if DEBUG
        case "setRendererLeadFrames":
            let frames = request.args["frames"].flatMap(Int.init)
            RendererLeadBudget.setFixedFramesOverride(frames)
            SurfaceInputProbes.record(
                "testcmd setRendererLeadFrames frames=\(frames.map(String.init) ?? "auto")",
                retention: .evidence
            )
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [RendererLeadBudget.currentFixedFramesOverride.map(String.init) ?? "auto"]
            )
        case "setSourceReadDelay":
            let milliseconds = request.args["ms"].flatMap(Int.init)
            MediaByteStreamServer.setDebugSourceReadDelay(milliseconds: milliseconds)
            SurfaceInputProbes.record(
                "testcmd setSourceReadDelay ms=\(milliseconds.map(String.init) ?? "none")",
                retention: .evidence
            )
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [MediaByteStreamServer.debugSourceReadDelayMilliseconds().map(String.init) ?? "none"]
            )
        case "probeStatus":
            let status = SurfaceInputProbes.status
            let healthy = status.fileBytes <= status.byteLimit
                && status.evidenceOverflowed == false
                && status.writeFailed == false
            return Response(
                id: request.id,
                ok: healthy,
                detail: healthy ? nil : "The DEBUG probe journal is unhealthy.",
                payload: [
                    "byteLimit=\(status.byteLimit)",
                    "fileBytes=\(status.fileBytes)",
                    "peakFileBytes=\(status.peakFileBytes)",
                    "compactionCount=\(status.compactionCount)",
                    "evidenceOverflowed=\(status.evidenceOverflowed)",
                    "writeFailed=\(status.writeFailed)"
                ]
            )
        case "armTransitionTrace":
            guard let logicalSessionID = playbackRuntime.activeSessionID else {
                throw CommandError(message: "armTransitionTrace requires active playback.")
            }
            let settlementFault: PlaybackRuntime.DebugPresentationSettlementFault?
            if let rawFault = request.args["fault"] {
                guard let fault = PlaybackRuntime.DebugPresentationSettlementFault(
                    rawValue: rawFault
                ) else {
                    throw CommandError(
                        message: "armTransitionTrace received an unsupported fault."
                    )
                }
                settlementFault = fault
            } else {
                settlementFault = nil
            }
            let generation = playbackSwitchStateRing.arm(
                context: PlaybackSwitchTraceContext(
                    logicalSessionID: logicalSessionID,
                    settledPresentation: playbackSession.playbackPresentation,
                    targetPresentation: playbackSession.presentationTransition?.targetPresentation
                ),
                byteStreamCounters: Self.switchCounters(
                    playbackRuntime.debugCurrentByteStreamCounters()
                )
            )
            playbackRuntime.debugSetPlaybackSwitchSampleHandler { [weak playbackSwitchStateRing] sample, counters in
                playbackSwitchStateRing?.record(
                    sample,
                    byteStreamCounters: Self.switchCounters(counters)
                )
            }
            if let settlementFault {
                playbackRuntime.debugArmPresentationSettlementFault(
                    settlementFault
                )
            }
            SurfaceInputProbes.record(
                "testcmd transitionTrace.arm generation=\(generation)"
                    + " fault=\(settlementFault?.rawValue ?? "none")",
                retention: .evidence
            )
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [
                    "generation=\(generation)",
                    "capacity=\(playbackSwitchStateRing.snapshot().capacity)",
                    "fault=\(settlementFault?.rawValue ?? "none")"
                ]
            )
        case "disarmTransitionTrace":
            let currentGeneration = playbackSwitchStateRing.snapshot().generation
            let requestedGeneration = request.args["generation"].flatMap(UInt64.init)
                ?? currentGeneration
            let disarmed = playbackSwitchStateRing.disarm(generation: requestedGeneration)
            if disarmed {
                playbackRuntime.debugSetPlaybackSwitchSampleHandler(nil)
                playbackRuntime.debugClearPresentationSettlementFault()
            }
            return Response(
                id: request.id,
                ok: disarmed,
                detail: disarmed ? nil : "The transition trace generation did not match.",
                payload: ["generation=\(requestedGeneration)"]
            )
        case "fetchTransitionTraceSnapshot":
            let snapshot = playbackSwitchStateRing.snapshot()
            if let generationToken = request.args["generationToken"], generationToken.isEmpty == false {
                guard String(snapshot.generation) == generationToken else {
                    throw CommandError(message: "transition snapshot generation does not match arm token.")
                }
            }
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [
                    "generation=\(snapshot.generation)",
                    "records=\(snapshot.records.count)",
                    "overwritten=\(snapshot.overwrittenRecordCount)"
                ],
                transitionTraceSnapshot: snapshot,
                transitionTraceAnalysis: .derive(from: snapshot)
            )
        case "embyServerIdentityDigest":
            guard let server = embySession.server else {
                throw CommandError(message: "No authenticated Emby server is configured.")
            }
            let digest = SHA256.hash(data: Data(server.id.rawValue.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [digest]
            )
        case "embySignIn":
            let cleanup = EmbyRuntimeIdentityCleanup(
                fileURL: embyRuntimeIdentityURL,
                fileManager: fileManager
            )
            return try await cleanup.perform {
                guard let identityDigest = request.args["identityDigest"],
                      identityDigest.hasPrefix("sha256:"),
                      identityDigest.count == "sha256:".count + 64,
                      identityDigest.dropFirst("sha256:".count).allSatisfy({
                          "0123456789abcdef".contains($0)
                      }) else {
                    throw CommandError(
                        message: "embySignIn requires a canonical identity digest."
                    )
                }
                guard fileManager.fileExists(atPath: embyRuntimeIdentityURL.path) else {
                    throw CommandError(
                        message: "The staged Emby runtime identity is unavailable."
                    )
                }
                let attributes = try fileManager.attributesOfItem(
                    atPath: embyRuntimeIdentityURL.path
                )
                guard let permissions = attributes[.posixPermissions] as? NSNumber,
                      permissions.intValue & 0o777 == 0o600 else {
                    throw CommandError(
                        message: "The staged Emby runtime identity must use mode 0600."
                    )
                }
                let identityData = try Data(contentsOf: embyRuntimeIdentityURL)
                let receipt = try await embySession.embySignIn(
                    identityData: identityData,
                    expectedIdentityDigest: identityDigest
                )
                return Response(
                    id: request.id,
                    ok: true,
                    detail: nil,
                    payload: nil,
                    embySignInReceipt: receipt
                )
            }
        case "artworkProbe":
            return try artworkProbe(request)
        case "containerIndexProbe":
            return containerIndexProbe(request)
        case "viewingStorageProbe":
            let snapshot = ViewingStorageDiagnosticSnapshot(
                viewingState: await playbackLauncher.debugViewingStateSnapshot(),
                containerIndex: ContainerIndexCache.shared.debugSnapshot(),
                artwork: ArtworkStore.shared.debugSnapshot(),
                mediaLibrary: mediaLibrary,
                settings: settings,
                playbackRuntime: playbackRuntime
            )
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: nil,
                viewingStorageSnapshot: snapshot
            )
        case "certificateTrustProbe":
            guard let address = request.args["address"], address.isEmpty == false,
                  let expectedPrevious = request.args["expectedPrevious"],
                  let expectedCurrent = request.args["expectedCurrent"] else {
                throw CommandError(
                    message: "certificateTrustProbe requires address and both fingerprints."
                )
            }
            let canonical: (String) -> String? = { value in
                let hex = value.hasPrefix("sha256:")
                    ? String(value.dropFirst("sha256:".count))
                    : value
                let compact = hex.filter(\.isHexDigit).lowercased()
                return compact.count == 64 ? "sha256:\(compact)" : nil
            }
            guard let previousFingerprint = canonical(expectedPrevious),
                  let currentFingerprint = canonical(expectedCurrent),
                  previousFingerprint != currentFingerprint else {
                throw CommandError(
                    message: "certificateTrustProbe requires two distinct SHA-256 fingerprints."
                )
            }
            let key = "server-certificate-fingerprint.\(address)"
            let stored = defaults.string(forKey: key)
            let storedFingerprint = stored.flatMap(canonical)
            let storedReport = storedFingerprint
                ?? (stored == nil ? "none" : "unrecognized")
            let currentFingerprintTrusted = storedFingerprint == currentFingerprint
            let storedMatchesPrevious = storedFingerprint == previousFingerprint
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [
                    "schema=enchron.regression.certificate-trust-probe@1",
                    "storedFingerprint=\(storedReport)",
                    "previousFingerprint=\(previousFingerprint)",
                    "currentFingerprint=\(currentFingerprint)",
                    "currentFingerprintTrusted=\(currentFingerprintTrusted)",
                    "storedMatchesPreviousFingerprint=\(storedMatchesPrevious)"
                ]
            )
#endif
        case "toggleControls":
            let requestedVisibility = request.args["visible"].flatMap(Bool.init)
            if requestedVisibility == nil || requestedVisibility != playbackSession.showControls {
                playbackSession.toggleControlsFromPlaybackSurface()
            }
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [String(playbackSession.showControls)]
            )
#if DEBUG
        case "closeMainWindow":
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.session.role == .windowApplication
                    && $0.activationState == .foregroundActive }) else {
                throw CommandError(message: "closeMainWindow found no foreground Window scene.")
            }
            SurfaceInputProbes.record(
                "testcmd closeMainWindow session=\(windowScene.session.persistentIdentifier)",
                retention: .evidence
            )
            UIApplication.shared.requestSceneSessionDestruction(
                windowScene.session,
                options: nil
            )
            return Response(id: request.id, ok: true, detail: nil, payload: [])
        case "setWindowSize":
            return try setWindowSize(request)
        case "openEnvironmentCard":
            let requested = try playbackSession.requestEnvironmentCard(
                mediaSessionID: playbackRuntime.activeSessionID,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
            return Response(
                id: request.id,
                ok: requested,
                detail: requested ? nil : "The environment card request was already pending.",
                payload: [String(describing: playbackSession.environmentCardResidency)]
            )
        case "dismissEnvironmentCard":
            playbackSession.environmentCardDismissalRequestRevision &+= 1
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [String(playbackSession.environmentCardDismissalRequestRevision)]
            )
        case "previewEnvironment":
            guard let rawEnvironment = request.args["environment"],
                  rawEnvironment.isEmpty == false,
                  let environment = SpatialSceneDomain.CinemaEnvironment(
                    rawValue: rawEnvironment
                  ) else {
                throw CommandError(
                    message: "previewEnvironment requires a valid environment argument."
                )
            }
            let effect = request.args["effect"].flatMap {
                SpatialSceneDomain.EnvironmentEffect(rawValue: $0)
            }
            try playbackSession.playbackPresentationModel.requestEnvironmentPreview(
                environment: environment,
                effect: effect
            )
            SurfaceInputProbes.record(
                "testcmd previewEnvironment environment=\(rawEnvironment)"
                    + " effect=\(effect?.rawValue ?? "none")",
                retention: .evidence
            )
            return Response(id: request.id, ok: true, detail: nil, payload: [rawEnvironment])
        case "dismissEnvironmentPreview":
            try playbackSession.playbackPresentationModel
                .requestEnvironmentPreviewDismissal()
            SurfaceInputProbes.record(
                "testcmd dismissEnvironmentPreview",
                retention: .evidence
            )
            return Response(id: request.id, ok: true, detail: nil, payload: [])
        case "playMedia":
            guard let name = request.args["name"], name.isEmpty == false else {
                throw CommandError(message: "playMedia requires a name argument.")
            }
            guard let reference = allReferences.first(where: { $0.name == name }) else {
                throw CommandError(
                    message: "playMedia found no library reference named \(name)."
                )
            }
            mediaLibrary.play(reference)
            SurfaceInputProbes.record(
                "testcmd playMedia name=\(name)",
                retention: .evidence
            )
            return Response(id: request.id, ok: true, detail: nil, payload: [name])
        case "enterSpatial":
            guard let target = playbackSession.playbackPresentation.enterImmersiveTarget else {
                throw CommandError(message: "enterSpatial requires window playback.")
            }
            let environment = try request.args["environment"].map { rawEnvironment in
                guard let environment = SpatialSceneDomain.CinemaEnvironment(
                    rawValue: rawEnvironment
                ) else {
                    throw CommandError(
                        message: "enterSpatial environment= must be a valid environment."
                    )
                }
                return environment
            }
            let effect = try request.args["effect"].map { rawEffect in
                guard let effect = SpatialSceneDomain.EnvironmentEffect(
                    rawValue: rawEffect
                ) else {
                    throw CommandError(
                        message: "enterSpatial effect= must be a valid effect."
                    )
                }
                return effect
            }
            let entry = try playbackSession.requestPlaybackPresentation(
                target,
                environment: environment,
                effect: effect,
                mediaSessionID: playbackRuntime.activeSessionID,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
            SurfaceInputProbes.record(
                "testcmd enterSpatial delivered target=\(target) transition=\(entry.id)",
                retention: .evidence
            )
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [String(describing: target), entry.id.uuidString]
            )
        case "exitSpatial":
            guard let target = playbackSession.playbackPresentation.exitImmersiveTarget else {
                throw CommandError(message: "exitSpatial requires immersive playback.")
            }
            let transition = try playbackSession.requestPlaybackPresentation(
                target,
                mediaSessionID: playbackRuntime.activeSessionID,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
            SurfaceInputProbes.record(
                "testcmd exitSpatial delivered target=\(target) transition=\(transition.id)",
                retention: .evidence
            )
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [String(describing: target), transition.id.uuidString]
            )
        case "connectWebDAV":
            guard let address = request.args["url"], address.isEmpty == false else {
                throw CommandError(message: "connectWebDAV requires a url argument.")
            }
            let sourceName = request.args["name"].flatMap { $0.isEmpty ? nil : $0 } ?? address
            let connectionInfo = try FileBrowsingDomain.ConnectionInfo.remote(
                sourceType: .webDAV,
                address: address
            )
            let dataSource = FileBrowsingDomain.DataSource(
                name: sourceName,
                sourceType: .webDAV,
                connectionInfo: connectionInfo
            )
            fileBrowser.addDataSource(dataSource)
            let result = await fileBrowser.connectToDataSource(dataSource)
            SurfaceInputProbes.record(
                "testcmd connectWebDAV url=\(address) result=\(String(describing: result))",
                retention: .evidence
            )
            return Response(
                id: request.id,
                ok: result == .connected,
                detail: result == .connected
                    ? nil
                    : "connectWebDAV returned \(result).",
                payload: [
                    "sourceID=\(dataSource.id.uuidString)",
                    "result=\(result)"
                ] + fileBrowser.files.map(\.name)
            )
        case "playRemoteFile":
            guard let name = request.args["name"], name.isEmpty == false else {
                throw CommandError(message: "playRemoteFile requires a name argument.")
            }
            guard let file = fileBrowser.files.first(where: { $0.name == name }) else {
                throw CommandError(
                    message: "playRemoteFile found no remote file named \(name)."
                )
            }
            fileBrowser.lastErrorMessage = nil
            fileBrowser.selectFile(file)
            SurfaceInputProbes.record(
                "testcmd playRemoteFile name=\(name)",
                retention: .evidence
            )
            var acceptance = "timeout"
            for _ in 0..<50 {
                if fileBrowser.lastErrorMessage != nil {
                    acceptance = "error"
                    break
                }
                if playbackLauncher.pendingResumeDecision != nil {
                    acceptance = "pendingResumeDecision"
                    break
                }
                if playbackRuntime.currentLaunchRequest != nil {
                    acceptance = "launchRequest"
                    break
                }
                try await Task.sleep(for: .milliseconds(400))
            }
            SurfaceInputProbes.record(
                "testcmd playRemoteFile acceptance=\(acceptance)",
                retention: .evidence
            )
            return Response(
                id: request.id,
                ok: acceptance == "launchRequest" || acceptance == "pendingResumeDecision",
                detail: fileBrowser.lastErrorMessage,
                payload: [
                    "acceptance=\(acceptance)",
                    "session=\(playbackRuntime.activeSessionID ?? "none")",
                    "pendingResume=\(playbackLauncher.pendingResumeDecision != nil)"
                ]
            )
        case "scrollEmby":
            return try scrollEmby(request)
        case "showPlaybackIssue":
            return try showPlaybackIssue(request)
        case "showFileBrowserError":
            return try showFileBrowserError(request)
        case "setFileBrowserAlertField":
            return try setFileBrowserAlertField(request)
        case "seekNormalized":
            return try seekNormalized(request)
        case "frameStep":
            return try frameStep(request)
        case "setDockedPlacement":
            return try setDockedPlacement(request)
        case "listMenuItems":
            return try performMenuSelection(request, operation: .list)
        case "selectMenuItem":
            guard let target = request.args["target"], target.isEmpty == false else {
                throw CommandError(
                    message: "selectMenuItem requires a target argument."
                )
            }
            return try performMenuSelection(
                request,
                operation: .select(target: target)
            )
        case "toggleBlackoutProbeWindow":
            playbackSession.showBlackoutProbeWindow.toggle()
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: [String(playbackSession.showBlackoutProbeWindow)]
            )
#endif
        case "setViewMode":
            guard let mode = request.args["mode"], mode.isEmpty == false else {
                throw CommandError(
                    message: "setViewMode requires a mode argument."
                )
            }
            switch mode {
            case "grid":
                mediaLibraryUIState.viewMode = .grid
            case "list":
                mediaLibraryUIState.viewMode = .list
            default:
                throw CommandError(
                    message: "setViewMode mode must be grid or list."
                )
            }
            return Response(
                id: request.id,
                ok: true,
                detail: "View mode set to \(mode) without a product gesture.",
                payload: nil
            )
        case "setDeveloperMode":
            guard let enabled = request.args["enabled"].flatMap(Bool.init) else {
                throw CommandError(
                    message: "setDeveloperMode requires enabled=true or enabled=false."
                )
            }
            settings.update { $0.developerModeEnabled = enabled }
            return Response(
                id: request.id,
                ok: true,
                detail: "Developer mode set to \(enabled) without a product gesture.",
                payload: nil
            )
        case "leavePlayback":
            await playbackRuntime.leavePlaybackAndWait(reason: .backButton)
            return Response(
                id: request.id,
                ok: true,
                detail: "Left playback without a product gesture.",
                payload: nil
            )
        case "resetState":
            await embySession.signOut()
            let references = allReferences
            for reference in references {
                mediaLibrary.remove(reference)
            }
            mediaLibrary.navigateToRoot()
            let folders = mediaLibrary.allFolders
            for folder in folders.reversed() {
                mediaLibrary.remove(folder)
            }
            let savedSourceCount = fileBrowser.savedDataSources.count
            for id in fileBrowser.savedDataSources.map(\.id) {
                fileBrowser.removeDataSource(id: id)
            }
            let removedSavedSourceCount = savedSourceCount - fileBrowser.savedDataSources.count
            let keys = ProductStateResetReceipt.managedDefaultKeys(in: defaults)
            for key in keys {
                defaults.removeObject(forKey: key)
            }
            mediaLibraryUIState.viewMode = .grid
            var createdFolderNames: [String] = []
            if let folderName = request.args["libraryFolder"],
               folderName.isEmpty == false {
                mediaLibrary.createFolder(named: folderName)
                if let detail = mediaLibrary.lastErrorMessage {
                    throw CommandError(message: detail)
                }
                createdFolderNames.append(folderName)
            }
            let remainingReferences = allReferences
            let remainingFolders = mediaLibrary.allFolders
            let remainingKeys = ProductStateResetReceipt.managedDefaultKeys(in: defaults)
            return Response(
                id: request.id,
                ok: true,
                detail: "Removed \(references.count) library references, "
                    + "removed \(folders.count) library folders, "
                    + "removed \(removedSavedSourceCount) saved remote sources, and "
                    + "deleted \(keys.count) managed defaults keys.",
                payload: libraryState,
                productStateResetReceipt: ProductStateResetReceipt(
                    removedReferenceCount: references.count,
                    removedFolderCount: folders.count,
                    removedManagedDefaultKeys: keys,
                    remainingReferenceCount: remainingReferences.count,
                    remainingFolderCount: remainingFolders.count,
                    remainingManagedDefaultKeys: remainingKeys,
                    createdFolderNames: createdFolderNames
                )
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
        case "importMediaDirectory":
            guard let directoryName = request.args["directory"],
                  let mediaFileName = request.args["media"],
                  let memberFileNamesJSON = request.args["files"],
                  let encodedMemberFileNames = memberFileNamesJSON.data(using: .utf8),
                  let memberFileNames = try? JSONDecoder().decode(
                    [String].self,
                    from: encodedMemberFileNames
                  ) else {
                throw CommandError(
                    message: "importMediaDirectory requires directory, media, and a files JSON array."
                )
            }
            let source = try TestMediaDirectorySource(
                directoryName: directoryName,
                mediaFileName: mediaFileName,
                memberFileNames: memberFileNames
            )
            let directoryURL = try source.materialize(
                in: inboxURL,
                fileManager: fileManager
            )
            let referenceIDsBeforeImport = Set(allReferences.map(\.id))
            await mediaLibrary.addFolder(directoryURL)
            if let detail = mediaLibrary.lastErrorMessage {
                throw CommandError(message: detail)
            }
            let additions = allReferences.filter {
                referenceIDsBeforeImport.contains($0.id) == false
            }
            guard additions.count == 1,
                  let reference = additions.first,
                  reference.name == mediaFileName else {
                throw CommandError(
                    message: "The production directory import pipeline did not add exactly one requested media reference."
                )
            }
            let receipt = try DirectoryMediaImportReceipt(
                source: source,
                reference: reference,
                fileManager: fileManager
            )
            return Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: allReferenceNames,
                directoryMediaImportReceipt: receipt
            )
        case "listLibrary":
            var response = Response(
                id: request.id,
                ok: true,
                detail: nil,
                payload: libraryState,
                librarySnapshot: LibraryEvidenceSnapshot(
                    library: mediaLibrary.library,
                    folders: mediaLibrary.allFolders,
                    inboxURL: inboxURL,
                    fileManager: fileManager
                )
            )
#if DEBUG
            response.systemImportDeliverySnapshot =
                SystemImportDeliveryDiagnostics.latestSnapshot
#endif
            return response
        default:
            throw CommandError(
                message: "Unknown app command verb: \(request.verb)."
            )
        }
    }

#if DEBUG
    private func artworkProbe(_ request: Request) throws -> Response {
        let currentIdentity = playbackRuntime.currentLaunchRequest?
            .versionedIdentity?.mediaIdentity
        let key: ArtworkKey
        if let requested = request.args["key"] {
            guard let parsed = ArtworkKey(debugStorageKey: requested) else {
                throw CommandError(
                    message: "artworkProbe key must be one exact media artwork key."
                )
            }
            key = parsed
        } else if let currentIdentity {
            key = ArtworkKey(mediaIdentity: currentIdentity)
        } else {
            throw CommandError(
                message: "artworkProbe requires active playback or an exact key."
            )
        }

        let currentKey = currentIdentity.map { ArtworkKey(mediaIdentity: $0) }
        let current: ArtworkDebugIdentity? = if currentKey == key,
                                                let image = playbackRuntime.displayedArtworkImage() {
            try ArtworkStore.shared.debugEncodedIdentity(image, for: key)
        } else {
            nil
        }
        let stored = ArtworkStore.shared.debugStoredIdentity(for: key)
        let counters = currentKey == key
            ? playbackRuntime.debugCurrentByteStreamCounters()
            : nil
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: [
                "schema=enchron.regression.artwork-probe@1",
                "artworkKey=\(key.debugStorageKey)",
                "currentDigest=\(current?.digest ?? "none")",
                "storedDigest=\(stored?.digest ?? "none")",
                "currentWidth=\(current?.width ?? 0)",
                "currentHeight=\(current?.height ?? 0)",
                "storedBytes=\(stored?.bytes ?? 0)",
                "byteStreamScope=\(counters.map { String($0.scope) } ?? "none")",
                "byteStreamRequestCount=\(counters.map { String($0.requestCount) } ?? "none")"
            ]
        )
    }

    private func containerIndexProbe(_ request: Request) -> Response {
        let snapshot = ContainerIndexCache.shared.debugSnapshot()
        let launch = playbackRuntime.currentLaunchRequest
        let addressKind: String
        if let launch {
            if launch.source.isRemote == false {
                addressKind = "local-file"
            } else {
                addressKind = switch launch.source.url.host?.lowercased() {
                case "127.0.0.1", "::1": "loopback"
                default: "remote-url"
                }
            }
        } else {
            addressKind = "none"
        }
        let sourceIdentity = launch?.versionedIdentity.map {
            "sha256:" + $0.mediaIdentity.storageKey
        } ?? "none"
        let contentRevision = launch?.versionedIdentity.map {
            "sha256:" + $0.contentRevision.storageKey
        } ?? "none"
        let counters = playbackRuntime.debugCurrentByteStreamCounters()
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: [
                "schema=enchron.regression.container-index-probe@1",
                "cacheDigest=\(snapshot.digest)",
                "entryKeys=\(snapshot.entries.map(\.contentRevision).joined(separator: ","))",
                "entryCount=\(snapshot.entries.count)",
                "totalBytes=\(snapshot.totalBytes)",
                "playbackAddressKind=\(addressKind)",
                "sourceIdentity=\(sourceIdentity)",
                "contentRevision=\(contentRevision)",
                "session=\(playbackRuntime.activeSessionID ?? "none")",
                "mediaName=\((launch?.displayName ?? "none").replacingOccurrences(of: ";", with: ","))",
                "byteStreamScope=\(counters.map { String($0.scope) } ?? "none")",
                "byteStreamRequestCount=\(counters.map { String($0.requestCount) } ?? "none")"
            ]
        )
    }
#endif

#if DEBUG && os(visionOS)
    private func performMenuSelection(
        _ request: Request,
        operation: DebugMenuSelectionRequest.Operation
    ) throws -> Response {
        guard let hostText = request.args["host"],
              let host = DebugMenuSelectionHost(rawValue: hostText) else {
            throw CommandError(
                message: "\(request.verb) requires host="
                    + DebugMenuSelectionHost.allCases.map(\.rawValue).joined(separator: "|")
                    + "."
            )
        }
        guard let familyText = request.args["family"],
              let family = DebugMenuSelectionFamily(rawValue: familyText) else {
            throw CommandError(
                message: "\(request.verb) requires family="
                    + DebugMenuSelectionFamily.allCases.map(\.rawValue).joined(separator: "|")
                    + "."
            )
        }

        let menuRequest = DebugMenuSelectionRequest(
            host: host,
            family: family,
            operation: operation
        )
        NotificationCenter.default.post(
            name: .debugMenuSelection,
            object: menuRequest
        )

        switch operation {
        case .list:
            guard let items = menuRequest.items else {
                throw CommandError(
                    message: "No visible \(host.rawValue) host accepted family="
                        + family.rawValue + "."
                )
            }
            return menuResponse(
                request: request,
                host: host,
                family: family,
                items: items
            )
        case .select(let target):
            guard let selectedItem = menuRequest.selectedItem else {
                if let items = menuRequest.items {
                    let available = items.map(\.id).joined(separator: ",")
                    throw CommandError(
                        message: "\(host.rawValue).\(family.rawValue) has no target="
                            + target + "; available=" + available + "."
                    )
                }
                throw CommandError(
                    message: "No visible \(host.rawValue) host accepted family="
                        + family.rawValue + "."
                )
            }
            return menuResponse(
                request: request,
                host: host,
                family: family,
                items: [selectedItem]
            )
        }
    }

    private func menuResponse(
        request: Request,
        host: DebugMenuSelectionHost,
        family: DebugMenuSelectionFamily,
        items: [DebugMenuSelectionSnapshot]
    ) -> Response {
        Response(
            id: request.id,
            ok: true,
            detail: "host=\(host.rawValue) family=\(family.rawValue)",
            payload: items.map(\.id),
            menuItems: items.map {
                Response.MenuItem(
                    id: $0.id,
                    title: $0.title,
                    isSelected: $0.isSelected
                )
            }
        )
    }

    private func seekNormalized(_ request: Request) throws -> Response {
        guard let positionText = request.args["position"],
              let position = Double(positionText),
              position.isFinite,
              (0...1).contains(position) else {
            throw CommandError(
                message: "seekNormalized requires position between 0 and 1."
            )
        }
        let duration = playbackRuntime.playbackPosition.duration
        guard duration > 0 else {
            throw CommandError(message: "seekNormalized requires active playback.")
        }
        let seconds = position * duration
        playbackRuntime.seek(to: seconds, event: .progressBar)
        SurfaceInputProbes.record(
            "testcmd seekNormalized delivered position=\(position) seconds=\(seconds)",
            retention: .evidence
        )
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: [String(position), String(seconds)]
        )
    }

    private func frameStep(_ request: Request) throws -> Response {
        let direction = request.args["direction"] ?? "forward"
        guard direction == "forward" || direction == "backward" else {
            throw CommandError(message: "frameStep requires direction=forward or direction=backward.")
        }
        guard let count = Int(request.args["count"] ?? "1"), count >= 1,
              let intervalMillis = Int(request.args["intervalMillis"] ?? "0"), intervalMillis >= 0 else {
            throw CommandError(message: "frameStep requires count >= 1 and intervalMillis >= 0.")
        }
        guard playbackRuntime.playbackPosition.duration > 0 else {
            throw CommandError(message: "frameStep requires active playback.")
        }
        let runtime = playbackRuntime
        Task { @MainActor in
            for index in 0..<count {
                if direction == "forward" {
                    runtime.frameStepForward()
                } else {
                    runtime.frameStepBackward()
                }
                if index + 1 < count, intervalMillis > 0 {
                    try? await Task.sleep(for: .milliseconds(intervalMillis))
                }
            }
        }
        SurfaceInputProbes.record(
            "testcmd frameStep delivered direction=\(direction) count=\(count) intervalMillis=\(intervalMillis)",
            retention: .evidence
        )
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: [direction, String(count), String(intervalMillis)]
        )
    }

    private func setDockedPlacement(_ request: Request) throws -> Response {
        guard playbackSession.playbackPresentation == .docked else {
            throw CommandError(message: "setDockedPlacement requires Docked playback.")
        }
        guard let axis = request.args["axis"],
              let valueText = request.args["value"],
              let value = Double(valueText),
              value.isFinite else {
            throw CommandError(
                message: "setDockedPlacement requires axis and finite value arguments."
            )
        }
        let applied: Double
        switch axis {
        case "screenSize":
            guard playbackSession.dockedPlacementLimits.screenHeightRange.contains(value) else {
                throw CommandError(message: "screenSize is outside its product range.")
            }
            playbackSession.setScreenScale(value)
            applied = playbackSession.screenScale
        case "distance":
            guard playbackSession.dockedPlacementLimits.distanceRange.contains(value) else {
                throw CommandError(message: "distance is outside its product range.")
            }
            playbackSession.setScreenDistance(value)
            applied = playbackSession.screenDepthOffset
        case "elevation":
            guard playbackSession.dockedPlacementLimits.elevationRange.contains(value) else {
                throw CommandError(message: "elevation is outside its product range.")
            }
            playbackSession.setScreenElevation(value)
            applied = playbackSession.screenViewAngle
        default:
            throw CommandError(
                message: "setDockedPlacement axis must be screenSize|distance|elevation."
            )
        }
        SurfaceInputProbes.record(
            "testcmd setDockedPlacement delivered axis=\(axis) value=\(applied)",
            retention: .evidence
        )
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: [axis, String(applied)]
        )
    }

    private func showPlaybackIssue(_ request: Request) throws -> Response {
        guard let category = request.args["category"] else {
            throw CommandError(
                message: "showPlaybackIssue requires a category argument."
            )
        }
        let issue: PlaybackUserVisibleIssue
        if let cause = PlaybackActiveFailure.Cause(rawValue: category) {
            guard let requestID = playbackRuntime.currentLaunchRequest?.id,
                  let mediaSessionID = playbackRuntime.activeSessionID else {
                throw CommandError(
                    message: "showPlaybackIssue active failures require an active media session."
                )
            }
            issue = .activePlaybackFailure(
                PlaybackActiveFailure(
                    cause: cause,
                    causalPosition: playbackRuntime.playbackPosition,
                    runtimeGeneration: playbackRuntime.observationGeneration,
                    requestID: requestID,
                    mediaSessionID: mediaSessionID
                )
            )
        } else {
            issue = switch category {
            case "mediaOpeningFailed": .mediaOpeningFailed
            case "playbackControlFailed": .playbackControlFailed
            case "presentationConversionFailed": .presentationConversionFailed
            case "surfaceAttachmentFailed": .surfaceAttachmentFailed
            case "environmentLoadingFailed": .environmentLoadingFailed
            case "capabilityUnavailable":
                .capabilityUnavailable(.videoDecoderUnavailable)
            default:
                throw CommandError(
                    message: "showPlaybackIssue does not support category \(category)."
                )
            }
        }
        playbackRuntime.setUserVisibleIssue(issue)
        SurfaceInputProbes.record(
            "testcmd showPlaybackIssue delivered category=\(category)",
            retention: .evidence
        )
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: [category]
        )
    }

    private func scrollEmby(_ request: Request) throws -> Response {
        guard let page = request.args["page"],
              ["home", "library", "search", "detail"].contains(page) else {
            throw CommandError(
                message: "scrollEmby requires page=home|library|search|detail."
            )
        }
        guard let directionText = request.args["direction"],
              let direction = EmbyReachabilityScrollRequest.Direction(
                  rawValue: directionText
              ) else {
            throw CommandError(
                message: "scrollEmby requires direction=forward|backward."
            )
        }
        let scrollRequest = EmbyReachabilityScrollRequest(
            page: page,
            direction: direction
        ) { deliveredPage in
            SurfaceInputProbes.record(
                "testcmd scrollEmby delivered page=\(deliveredPage)"
                    + " direction=\(direction.rawValue)",
                retention: .evidence
            )
        }
        NotificationCenter.default.post(
            name: .embyReachabilityScroll,
            object: scrollRequest
        )
        guard let handledPage = scrollRequest.handledPage else {
            throw CommandError(
                message: "No visible Emby page accepted scrollEmby page=\(page)."
            )
        }
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: [handledPage, direction.rawValue]
        )
    }

    private func showFileBrowserError(_ request: Request) throws -> Response {
        let message = request.args["message"] ?? "Reachability verification error"
        let errorRequest = FileBrowserReachabilityErrorRequest(message: message)
        NotificationCenter.default.post(
            name: .fileBrowserReachabilityError,
            object: errorRequest
        )
        guard errorRequest.wasHandled else {
            throw CommandError(
                message: "No visible Files screen accepted showFileBrowserError."
            )
        }
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: [message]
        )
    }

    private func setFileBrowserAlertField(_ request: Request) throws -> Response {
        guard let fieldText = request.args["field"],
              let field = FileBrowserAlertFieldRequest.Field(rawValue: fieldText),
              let value = request.args["value"] else {
            throw CommandError(
                message: "setFileBrowserAlertField requires "
                    + "field=newFolderName|renameFolderName and value."
            )
        }
        let fieldRequest = FileBrowserAlertFieldRequest(
            field: field,
            value: value
        )
        NotificationCenter.default.post(
            name: .fileBrowserAlertField,
            object: fieldRequest
        )
        guard fieldRequest.wasHandled else {
            throw CommandError(
                message: "No visible Files alert accepted field=\(field.rawValue)."
            )
        }
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: [field.rawValue]
        )
    }

    private func setWindowSize(_ request: Request) throws -> Response {
        guard playbackSession.playbackPresentation == .portal else {
            throw CommandError(message: "setWindowSize requires Portal playback.")
        }
        guard let widthText = request.args["width"],
              let heightText = request.args["height"],
              let width = Double(widthText),
              let height = Double(heightText),
              width.isFinite,
              height.isFinite else {
            throw CommandError(
                message: "setWindowSize requires finite width and height arguments."
            )
        }
        let size = CGSize(width: width, height: height)
        let bounds = WindowPlaybackLayout.fallback
        guard bounds.contains(size) else {
            throw CommandError(
                message: "setWindowSize must stay within playback window bounds "
                    + "\(bounds.minimumSize.width)x"
                    + "\(bounds.minimumSize.height)..."
                    + "\(bounds.maximumSize.width)x"
                    + "\(bounds.maximumSize.height)."
            )
        }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            throw CommandError(message: "setWindowSize found no foreground Window scene.")
        }

        playbackSession.recordSurfaceInputProbe(
            "setWindowSize requested=\(size.width)x\(size.height)"
        )
        windowScene.requestGeometryUpdate(
            UIWindowScene.GeometryPreferences.Vision(
                size: size,
                minimumSize: bounds.minimumSize,
                maximumSize: bounds.maximumSize,
                resizingRestrictions: .freeform
            )
        ) { [weak playbackSession] error in
            Task { @MainActor in
                playbackSession?.recordSurfaceInputProbe(
                    "setWindowSize failed error=\(error.localizedDescription)"
                )
            }
        }
        Task { @MainActor [weak playbackSession, weak windowScene] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let windowScene else { return }
            let applied = windowScene.effectiveGeometry.coordinateSpace.bounds.size
            playbackSession?.recordSurfaceInputProbe(
                "setWindowSize observed=\(applied.width)x\(applied.height)",
                retention: .evidence
            )
        }
        return Response(
            id: request.id,
            ok: true,
            detail: nil,
            payload: ["\(size.width)x\(size.height)"]
        )
    }
#elseif DEBUG
    private func setWindowSize(_ request: Request) throws -> Response {
        _ = request
        throw CommandError(message: "setWindowSize requires visionOS.")
    }
#endif

    private var allReferences: [FileBrowsingDomain.MediaReference] {
        let library = mediaLibrary.library
        return library.references(in: nil) + mediaLibrary.allFolders.flatMap {
            library.references(in: $0.id)
        }
    }

    private var allReferenceNames: [String] {
        allReferences.map(\.name)
    }

    private var libraryState: [String] {
        mediaLibrary.allFolders.map { "folder=\($0.name)" }
            + allReferenceNames.map { "reference=\($0)" }
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
                mediaLibraryUIState: application.mediaLibraryUIState,
                fileBrowser: application.fileBrowsingViewModel,
                playbackSession: application.playbackSessionModel,
                playbackRuntime: application.playbackRuntime,
                playbackLauncher: application.playbackLauncher,
                settings: application.settingsViewModel,
                embySession: application.embySessionViewModel
            )
            #if DEBUG
                channel.usePlaybackSwitchStateRing(application.playbackSwitchStateRing)
            #endif
            activeChannel = channel
            channel.start()
        } catch {
            SurfaceInputProbes.record(
                "testcmd channel failed error=\(error.localizedDescription)",
                retention: .evidence
            )
        }
    }
}

extension EnchronApplication {
    func installTestCommandChannelIfEnabled(environment: [String: String]) {
        TestCommandChannelBootstrap.installIfEnabled(
            environment: environment,
            application: self
        )
    }
}

#endif
