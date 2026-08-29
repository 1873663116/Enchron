import CoreTransferable
#if DEBUG
import CryptoKit
#endif
import Foundation
import UniformTypeIdentifiers

#if DEBUG
@MainActor
public enum SystemImportDeliveryDiagnostics {
    public enum DeliveryDomain: String, Encodable, Equatable, Sendable {
        case filesProviderSecurityScope = "files-provider-security-scope"
        case appManagedPhotoTransfer = "app-managed-photo-transfer"
    }

    public enum ReturnedIdentityKind: String, Encodable, Equatable, Sendable {
        case filesProviderURL = "files-provider-url"
        case photosAsset = "photos-asset"
    }

    public enum PersistenceOutcome: String, Encodable, Equatable, Sendable {
        case persisted
        case rejected
    }

    public struct DeliveredItem: Encodable, Equatable, Sendable {
        public let returnedIdentityKind: ReturnedIdentityKind
        public let returnedIdentity: String?
        public let deliveredName: String
        public let byteCount: Int64?
        public let sha256: String?

        init(
            returnedIdentityKind: ReturnedIdentityKind,
            returnedIdentity: String?,
            deliveredName: String,
            byteCount: Int64?,
            sha256: String?
        ) {
            self.returnedIdentityKind = returnedIdentityKind
            self.returnedIdentity = returnedIdentity
            self.deliveredName = deliveredName
            self.byteCount = byteCount
            self.sha256 = sha256
        }
    }

    public struct PersistentReference: Encodable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let locatorKind: String
        public let sizeInBytes: Int64

        init(
            id: String,
            name: String,
            locatorKind: String,
            sizeInBytes: Int64
        ) {
            self.id = id
            self.name = name
            self.locatorKind = locatorKind
            self.sizeInBytes = sizeInBytes
        }
    }

    public struct PersistentLibraryDelivery: Encodable, Equatable, Sendable {
        public let outcome: PersistenceOutcome
        public let references: [PersistentReference]
        public let errorDescription: String?

        init(
            outcome: PersistenceOutcome,
            references: [PersistentReference],
            errorDescription: String?
        ) {
            self.outcome = outcome
            self.references = references
            self.errorDescription = errorDescription
        }
    }

    public struct Snapshot: Encodable, Equatable, Sendable {
        public static let schemaValue = "enchron.regression.system-import-delivery@1"

        public let schema: String
        public let requestID: String
        public let routeIdentity: String
        public let deliveryDomain: DeliveryDomain
        public let items: [DeliveredItem]
        public let persistentLibraryDelivery: PersistentLibraryDelivery

        init(
            requestID: UUID,
            deliveryDomain: DeliveryDomain,
            items: [DeliveredItem],
            persistentLibraryDelivery: PersistentLibraryDelivery
        ) {
            let canonicalRequestID = requestID.uuidString.lowercased()
            schema = Self.schemaValue
            self.requestID = canonicalRequestID
            routeIdentity = "\(deliveryDomain.rawValue):\(canonicalRequestID)"
            self.deliveryDomain = deliveryDomain
            self.items = items
            self.persistentLibraryDelivery = persistentLibraryDelivery
        }
    }

    private struct PendingDelivery {
        let requestID: UUID
        let deliveryDomain: DeliveryDomain
        let deliveredURLs: [URL]
        let items: [DeliveredItem]
    }

    private static var requestedDomains: [UUID: DeliveryDomain] = [:]
    private static var pendingDeliveries: [PendingDelivery] = []
    private static var snapshot: Snapshot?

    public static var latestSnapshot: Snapshot? { snapshot }

    @discardableResult
    public static func beginRequest(deliveryDomain: DeliveryDomain) -> UUID {
        let requestID = UUID()
        requestedDomains[requestID] = deliveryDomain
        return requestID
    }

    public static func discardRequest(_ requestID: UUID) {
        requestedDomains.removeValue(forKey: requestID)
    }

    public static func recordFileImporterCompletion(
        requestID: UUID,
        deliveredURLs: [URL]
    ) {
        guard requestedDomains.removeValue(forKey: requestID)
                == .filesProviderSecurityScope,
              deliveredURLs.isEmpty == false else { return }
        pendingDeliveries.append(
            PendingDelivery(
                requestID: requestID,
                deliveryDomain: .filesProviderSecurityScope,
                deliveredURLs: deliveredURLs,
                items: deliveredURLs.map {
                    deliveredItem(
                        at: $0,
                        identityKind: .filesProviderURL,
                        returnedIdentity: $0.standardizedFileURL.path
                    )
                }
            )
        )
    }

    public static func recordPhotosTransferCompletion(
        requestID: UUID,
        assetIdentifier: String?,
        deliveredURL: URL
    ) {
        guard requestedDomains.removeValue(forKey: requestID)
                == .appManagedPhotoTransfer else { return }
        pendingDeliveries.append(
            PendingDelivery(
                requestID: requestID,
                deliveryDomain: .appManagedPhotoTransfer,
                deliveredURLs: [deliveredURL],
                items: [
                    deliveredItem(
                        at: deliveredURL,
                        identityKind: .photosAsset,
                        returnedIdentity: assetIdentifier
                    )
                ]
            )
        )
    }

    public static func recordPersistentLibraryDelivery(
        deliveredURLs: [URL],
        newReferences: [FileBrowsingDomain.MediaReference],
        errorDescription: String?
    ) {
        let deliveredPaths = deliveredURLs.map { $0.standardizedFileURL.path }
        guard let index = pendingDeliveries.lastIndex(where: {
            $0.deliveredURLs.map { $0.standardizedFileURL.path } == deliveredPaths
        }) else { return }
        let pending = pendingDeliveries.remove(at: index)
        let references = newReferences.map { reference in
            let locatorKind = switch reference.locator {
            case .file: "file"
            case .sourceItem: "sourceItem"
            }
            return PersistentReference(
                id: reference.id.uuidString.lowercased(),
                name: reference.name,
                locatorKind: locatorKind,
                sizeInBytes: reference.sizeInBytes
            )
        }
        let referencesMatchDelivery = references.count == pending.items.count
            && zip(references, pending.items).allSatisfy { reference, item in
                reference.locatorKind == "file"
                    && reference.name == item.deliveredName
                    && item.byteCount.map { reference.sizeInBytes == $0 } != false
            }
        let persisted = errorDescription == nil && referencesMatchDelivery
        let observedError = errorDescription ?? (persisted ? nil :
            "The persistent library did not publish every delivered item.")
        snapshot = Snapshot(
            requestID: pending.requestID,
            deliveryDomain: pending.deliveryDomain,
            items: pending.items,
            persistentLibraryDelivery: PersistentLibraryDelivery(
                outcome: persisted ? .persisted : .rejected,
                references: references,
                errorDescription: observedError
            )
        )
    }

    static func sha256(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func deliveredItem(
        at url: URL,
        identityKind: ReturnedIdentityKind,
        returnedIdentity: String?
    ) -> DeliveredItem {
        let accessStarted = url.startAccessingSecurityScopedResource()
        defer { if accessStarted { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey
        ])
        let isRegularFile = values?.isRegularFile == true
        return DeliveredItem(
            returnedIdentityKind: identityKind,
            returnedIdentity: returnedIdentity,
            deliveredName: url.lastPathComponent,
            byteCount: isRegularFile ? Int64(values?.fileSize ?? 0) : nil,
            sha256: isRegularFile ? fileDigest(url) : nil
        )
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
        return "sha256:" + hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
#endif

public enum ManagedMediaImportError: LocalizedError, Equatable, Sendable {
    case transferUnavailable
    case unsupportedMedia(filename: String)
    case copyFailed(filename: String)
    case persistenceFailed(filename: String)

    public var errorDescription: String? {
        switch self {
        case .transferUnavailable:
            "The selected video could not be loaded. It may still be downloading from iCloud."
        case .unsupportedMedia(let filename):
            "\(filename) is not a supported video."
        case .copyFailed(let filename):
            "Could not copy \(filename) into the Media Library."
        case .persistenceFailed(let filename):
            "Could not save \(filename) in the Media Library."
        }
    }
}

public struct AppManagedMediaFile: Equatable, Sendable, Transferable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(
            importedContentType: .movie,
            shouldAttemptToOpenInPlace: false
        ) { receivedFile in
            let url = try await importStore.importFile(at: receivedFile.file)
            return AppManagedMediaFile(url: url)
        }
    }

    private static let importStore = AppManagedMediaImportStore()
}

public actor AppManagedMediaImportStore {
    typealias MoveStagedFile = @Sendable (URL, URL) throws -> Void

    private let rootDirectory: URL?
    private let moveStagedFile: MoveStagedFile
    private let fileManager: FileManager

    fileprivate init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        rootDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appending(path: "Enchron", directoryHint: .isDirectory)
            .appending(path: "Managed Media", directoryHint: .isDirectory)
        moveStagedFile = { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        fileManager = .default
        moveStagedFile = { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    init(
        rootDirectory: URL,
        moveStagedFile: @escaping MoveStagedFile
    ) {
        self.rootDirectory = rootDirectory
        self.moveStagedFile = moveStagedFile
        fileManager = .default
    }

    public func importFile(at providerURL: URL) throws -> URL {
        let filename = providerURL.lastPathComponent
        guard Self.isSupportedVideo(providerURL) else {
            throw ManagedMediaImportError.unsupportedMedia(filename: filename)
        }
        do {
            let values = try providerURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw ManagedMediaImportError.copyFailed(filename: filename)
            }
        } catch let error as ManagedMediaImportError {
            throw error
        } catch {
            throw ManagedMediaImportError.copyFailed(filename: filename)
        }
        guard let rootDirectory else {
            throw ManagedMediaImportError.persistenceFailed(filename: filename)
        }

        let stagingRoot = rootDirectory.appending(
            path: ".staging",
            directoryHint: .isDirectory
        )
        let itemsRoot = rootDirectory.appending(
            path: "items",
            directoryHint: .isDirectory
        )
        let identifier = availableIdentifier(
            stagingRoot: stagingRoot,
            itemsRoot: itemsRoot
        )
        let stagingDirectory = stagingRoot.appending(
            path: identifier.uuidString,
            directoryHint: .isDirectory
        )
        let destinationDirectory = itemsRoot.appending(
            path: identifier.uuidString,
            directoryHint: .isDirectory
        )
        let stagedURL = stagingDirectory.appending(path: filename)
        let destinationURL = destinationDirectory.appending(path: filename)

        do {
            try fileManager.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            cleanUp(stagingDirectory, destinationDirectory)
            throw ManagedMediaImportError.persistenceFailed(filename: filename)
        }

        do {
            try fileManager.copyItem(at: providerURL, to: stagedURL)
        } catch {
            cleanUp(stagingDirectory, destinationDirectory)
            throw ManagedMediaImportError.copyFailed(filename: filename)
        }

        do {
            try moveStagedFile(stagedURL, destinationURL)
        } catch {
            cleanUp(stagingDirectory, destinationDirectory)
            throw ManagedMediaImportError.persistenceFailed(filename: filename)
        }

        try? fileManager.removeItem(at: stagingDirectory)
        return destinationURL
    }

    private static func isSupportedVideo(_ url: URL) -> Bool {
        guard FileBrowsingDomain.FileFilter.playable.matches(fileURL: url),
              let contentType = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return contentType.conforms(to: .movie)
    }

    private func availableIdentifier(
        stagingRoot: URL,
        itemsRoot: URL
    ) -> UUID {
        while true {
            let identifier = UUID()
            let component = identifier.uuidString
            let stagingPath = stagingRoot.appending(path: component).path
            let itemPath = itemsRoot.appending(path: component).path
            if fileManager.fileExists(atPath: stagingPath) == false,
               fileManager.fileExists(atPath: itemPath) == false {
                return identifier
            }
        }
    }

    private func cleanUp(_ urls: URL...) {
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}
