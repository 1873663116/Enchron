import Foundation

public nonisolated enum MediaLibrarySearch {
    public static func matches(
        _ folder: FileBrowsingDomain.LibraryFolder,
        query: String
    ) -> Bool {
        matchesVisibleName(folder.name, query: query)
    }

    public static func matches(
        _ reference: FileBrowsingDomain.MediaReference,
        query: String
    ) -> Bool {
        matchesVisibleName(
            (reference.name as NSString).deletingPathExtension,
            query: query
        )
    }

    private static func matchesVisibleName(_ name: String, query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedQuery.isEmpty
            || name.localizedCaseInsensitiveContains(normalizedQuery)
    }
}
