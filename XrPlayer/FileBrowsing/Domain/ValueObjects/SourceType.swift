import Foundation

public enum FileBrowsingDomain {}

extension FileBrowsingDomain {
    public enum SourceType: String, Sendable, CaseIterable, Codable {
        case local
        case photoLibrary
        case smb
        case webDAV
    }
}
