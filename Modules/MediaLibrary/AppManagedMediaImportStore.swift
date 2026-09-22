import CoreTransferable
import Foundation
import UniformTypeIdentifiers

public enum ManagedMediaImportError: LocalizedError, Equatable, Sendable {
    case transferUnavailable
    case unsupportedMedia(filename: String)
    case copyFailed(filename: String)
    case persistenceFailed(filename: String)

    public var errorDescription: String? {
        switch self {
        case .transferUnavailable:
            "The selected video could not be loaded. It may still be downloading from iCloud."
        case .unsupportedMedia(let filename):
            "\(filename) is not a supported video."
        case .copyFailed(let filename):
            "Could not copy \(filename) into the Media Library."
        case .persistenceFailed(let filename):
            "Could not save \(filename) in the Media Library."
        }
    }
}

public struct AppManagedMediaFile: Equatable, Sendable, Transferable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(
            importedContentType: .movie,
            shouldAttemptToOpenInPlace: false
        ) { receivedFile in
            let url = try await importStore.importFile(at: receivedFile.file)
            return AppManagedMediaFile(url: url)
        }
    }

    private static let importStore = AppManagedMediaImportStore()
}

public actor AppManagedMediaImportStore {
    typealias MoveStagedFile = @Sendable (URL, URL) throws -> Void

    private let rootDirectory: URL?
    private let moveStagedFile: MoveStagedFile
    private let fileManager: FileManager

    fileprivate init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        rootDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appending(path: "Enchron", directoryHint: .isDirectory)
            .appending(path: "Managed Media", directoryHint: .isDirectory)
        moveStagedFile = { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        fileManager = .default
        moveStagedFile = { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    init(
        rootDirectory: URL,
        moveStagedFile: @escaping MoveStagedFile
    ) {
        self.rootDirectory = rootDirectory
        self.moveStagedFile = moveStagedFile
        fileManager = .default
    }

    public func importFile(at providerURL: URL) throws -> URL {
        let filename = providerURL.lastPathComponent
        guard Self.isSupportedVideo(providerURL) else {
            throw ManagedMediaImportError.unsupportedMedia(filename: filename)
        }
        do {
            let values = try providerURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw ManagedMediaImportError.copyFailed(filename: filename)
            }
        } catch let error as ManagedMediaImportError {
            throw error
        } catch {
            throw ManagedMediaImportError.copyFailed(filename: filename)
        }
        guard let rootDirectory else {
            throw ManagedMediaImportError.persistenceFailed(filename: filename)
        }

        let stagingRoot = rootDirectory.appending(
            path: ".staging",
            directoryHint: .isDirectory
        )
        let itemsRoot = rootDirectory.appending(
            path: "items",
            directoryHint: .isDirectory
        )
        let identifier = availableIdentifier(
            stagingRoot: stagingRoot,
            itemsRoot: itemsRoot
        )
        let stagingDirectory = stagingRoot.appending(
            path: identifier.uuidString,
            directoryHint: .isDirectory
        )
        let destinationDirectory = itemsRoot.appending(
            path: identifier.uuidString,
            directoryHint: .isDirectory
        )
        let stagedURL = stagingDirectory.appending(path: filename)
        let destinationURL = destinationDirectory.appending(path: filename)

        do {
            try fileManager.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            cleanUp(stagingDirectory, destinationDirectory)
            throw ManagedMediaImportError.persistenceFailed(filename: filename)
        }

        do {
            try fileManager.copyItem(at: providerURL, to: stagedURL)
        } catch {
            cleanUp(stagingDirectory, destinationDirectory)
            throw ManagedMediaImportError.copyFailed(filename: filename)
        }

        do {
            try moveStagedFile(stagedURL, destinationURL)
        } catch {
            cleanUp(stagingDirectory, destinationDirectory)
            throw ManagedMediaImportError.persistenceFailed(filename: filename)
        }

        try? fileManager.removeItem(at: stagingDirectory)
        return destinationURL
    }

    private static func isSupportedVideo(_ url: URL) -> Bool {
        guard FileBrowsingDomain.FileFilter.playable.matches(fileURL: url),
              let contentType = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return contentType.conforms(to: .movie)
    }

    private func availableIdentifier(
        stagingRoot: URL,
        itemsRoot: URL
    ) -> UUID {
        while true {
            let identifier = UUID()
            let component = identifier.uuidString
            let stagingPath = stagingRoot.appending(path: component).path
            let itemPath = itemsRoot.appending(path: component).path
            if fileManager.fileExists(atPath: stagingPath) == false,
               fileManager.fileExists(atPath: itemPath) == false {
                return identifier
            }
        }
    }

    private func cleanUp(_ urls: URL...) {
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}
