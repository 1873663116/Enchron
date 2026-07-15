import Foundation

struct ResolvedSecurityScopedFile {
    let url: URL
    let access: PlaybackSourceAccess?
}

@MainActor
final class SecurityScopedFileReferenceResolver {
    enum ResolutionError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "The original file is unavailable. Choose it again to restore access."
        }
    }

    func resolve(bookmark: Data, relativePath: String) throws -> ResolvedSecurityScopedFile {
        var stale = false
        let selectedURL = try URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        let access = PlaybackSourceAccess.securityScoped(selectedURL)
        let playableURL = relativePath.isEmpty
            ? selectedURL
            : selectedURL.appending(path: relativePath)
        guard !stale, (try? playableURL.checkResourceIsReachable()) == true else {
            access?.release()
            throw ResolutionError.unavailable
        }
        return ResolvedSecurityScopedFile(url: playableURL, access: access)
    }
}
