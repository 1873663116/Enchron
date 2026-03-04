import Foundation

public final class KeychainStore: CredentialStoring {
    public init() {}

    public func saveCredential(for sourceID: String, credential: StorageCredential) throws {
        _ = sourceID
        _ = credential
        fatalError("TODO: implement")
    }

    public func loadCredential(for sourceID: String) throws -> StorageCredential? {
        _ = sourceID
        fatalError("TODO: implement")
    }

    public func deleteCredential(for sourceID: String) throws {
        _ = sourceID
        fatalError("TODO: implement")
    }
}
