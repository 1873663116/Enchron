import Foundation

public nonisolated enum FileBrowsingDomain {}

nonisolated extension FileBrowsingDomain {
    public enum SourceType: String, Sendable, CaseIterable, Codable {
        case local
        case photoLibrary
        case smb
        case webDAV
    }
}
