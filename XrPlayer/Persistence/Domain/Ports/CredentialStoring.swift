import Foundation

public struct StorageCredential: Sendable, Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public protocol CredentialStoring {
    func saveCredential(for sourceID: String, credential: StorageCredential) throws
    func loadCredential(for sourceID: String) throws -> StorageCredential?
    func deleteCredential(for sourceID: String) throws
}
