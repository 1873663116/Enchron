import Foundation
import MediaSource

nonisolated extension CredentialStoring {
    func loadCredential(
        for connectionInfo: FileBrowsingDomain.ConnectionInfo
    ) throws -> StorageCredential? {
        if let credential = try loadCredential(for: connectionInfo.credentialSourceID) {
            return credential
        }
        let legacySourceID = connectionInfo.legacyCredentialSourceID
        guard legacySourceID != connectionInfo.credentialSourceID,
              let credential = try loadCredential(for: legacySourceID) else { return nil }
        let expectedUsername = connectionInfo.username?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedUsername = credential.username
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedAccount = expectedUsername.isEmpty ? "guest" : expectedUsername
        let storedAccount = storedUsername.isEmpty ? "guest" : storedUsername
        guard storedAccount == expectedAccount else { return nil }
        try saveCredential(for: connectionInfo.credentialSourceID, credential: credential)
        try deleteCredential(for: legacySourceID)
        return credential
    }
}
