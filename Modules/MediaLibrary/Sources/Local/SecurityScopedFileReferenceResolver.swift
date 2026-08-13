import Foundation
import MediaSource

struct ResolvedSecurityScopedFile {
    let url: URL
    let access: MediaAccessLease?
}

@MainActor
final class SecurityScopedFileReferenceResolver {
    enum ResolutionError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "The original file is unavailable. Choose it again to restore access."
        }
    }

    nonisolated static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        []
        #else
        .minimalBookmark
        #endif
    }

    private nonisolated static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        []
    }

    func resolve(bookmark: Data, relativePath: String) throws -> ResolvedSecurityScopedFile {
        var stale = false
        let selectedURL = try URL(
            resolvingBookmarkData: bookmark,
            options: Self.bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        #if os(macOS)
        let access: MediaAccessLease? = nil
        #else
        let access = MediaAccessLease.securityScoped(selectedURL)
        #endif
        let playableURL: URL
        if relativePath.isEmpty {
            playableURL = selectedURL
        } else {
            let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            guard !relativePath.hasPrefix("/"),
                  components.allSatisfy({ component in
                      !component.isEmpty && component != "." && component != ".."
                  }) else {
                access?.release()
                throw ResolutionError.unavailable
            }
            playableURL = components.reduce(selectedURL) { partialURL, component in
                partialURL.appending(path: String(component))
            }
            let authorizedRootComponents = selectedURL.standardizedFileURL
                .resolvingSymlinksInPath().pathComponents
            let resolvedPlayableComponents = playableURL.standardizedFileURL
                .resolvingSymlinksInPath().pathComponents
            guard resolvedPlayableComponents.count > authorizedRootComponents.count,
                  resolvedPlayableComponents.starts(with: authorizedRootComponents) else {
                access?.release()
                throw ResolutionError.unavailable
            }
        }
        guard !stale, (try? playableURL.checkResourceIsReachable()) == true else {
            access?.release()
            throw ResolutionError.unavailable
        }
        return ResolvedSecurityScopedFile(url: playableURL, access: access)
    }
}
