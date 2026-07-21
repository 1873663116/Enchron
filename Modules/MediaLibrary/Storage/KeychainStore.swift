import Foundation
import Security


public nonisolated struct StorageCredential: Sendable, Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public nonisolated protocol CredentialStoring: Sendable {
    func saveCredential(for sourceID: String, credential: StorageCredential) throws
    func loadCredential(for sourceID: String) throws -> StorageCredential?
    func deleteCredential(for sourceID: String) throws
}


public nonisolated enum KeychainError: LocalizedError, Sendable {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save credential to Keychain (OSStatus: \(status))."
        case .loadFailed(let status):
            return "Failed to load credential from Keychain (OSStatus: \(status))."
        }
    }
}

public nonisolated final class KeychainStore: CredentialStoring, @unchecked Sendable {
    private struct CredentialPayload: Codable {
        let username: String
        let password: String
    }

    public init() {}

    public func saveCredential(for sourceID: String, credential: StorageCredential) throws {
        let payload = CredentialPayload(username: credential.username, password: credential.password)
        let jsonData: Data
        do {
            jsonData = try JSONEncoder().encode(payload)
        } catch {
            throw KeychainError.saveFailed(errSecParam)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: sourceID,
            kSecAttrAccount as String: "com.xrplayer.credentials"
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = jsonData
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    public func loadCredential(for sourceID: String) throws -> StorageCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: sourceID,
            kSecAttrAccount as String: "com.xrplayer.credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }
        guard let data = result as? Data else {
            throw KeychainError.loadFailed(errSecDecode)
        }

        do {
            let payload = try JSONDecoder().decode(CredentialPayload.self, from: data)
            return StorageCredential(username: payload.username, password: payload.password)
        } catch {
            throw KeychainError.loadFailed(errSecDecode)
        }
    }

    public func deleteCredential(for sourceID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: sourceID,
            kSecAttrAccount as String: "com.xrplayer.credentials"
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.saveFailed(status)
        }
    }
}

