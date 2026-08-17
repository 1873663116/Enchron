import Foundation
import MediaSource

struct ExternalSubtitleResolution {
    let sources: [ResolvedExternalSubtitleSource]
    let hadFailures: Bool

    static let none = ExternalSubtitleResolution(sources: [], hadFailures: false)
}

enum ExternalSubtitleAssociation {
    static func matching(
        mediaFile: FileBrowsingDomain.MediaFile,
        subtitleFiles: [FileBrowsingDomain.MediaFile]
    ) -> [FileBrowsingDomain.MediaFile] {
        let mediaBaseName = mediaFile.url.deletingPathExtension().lastPathComponent
        return subtitleFiles.filter { file in
            guard FileBrowsingDomain.FileFilter.externalSubtitles.matches(fileURL: file.url) else {
                return false
            }
            let subtitleBaseName = file.url.deletingPathExtension().lastPathComponent
            return subtitleBaseName == mediaBaseName
                || subtitleBaseName.hasPrefix(mediaBaseName + ".")
        }.sorted {
            NaturalMediaNameOrder.lessThan($0.name, id: $0.id, $1.name, id: $1.id)
        }
    }
}
