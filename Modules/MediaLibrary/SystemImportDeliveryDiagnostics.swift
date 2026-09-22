#if DEBUG
import CryptoKit
import Foundation

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
