import Foundation
import Observation

#if DEBUG
import DesignSystem
#endif

#if DEBUG
public enum FilesScreenAlertField: Sendable {
    case newFolderName
    case renameFolderName
}
#endif

public enum FilesScreenFileImportKind: Equatable, Sendable {
    case mediaFiles
    case folder

    func action(for urls: [URL]) -> FilesScreenFileImportAction {
        if self == .folder, let folder = urls.first {
            return .addFolder(folder)
        }
        return .addFiles(urls)
    }
}

enum FilesScreenFileImportAction: Equatable, Sendable {
    case addFiles([URL])
    case addFolder(URL)
}

public enum FilesScreenProductEntry: Equatable, Sendable {
    case fileImporter(FilesScreenFileImportKind)
    case photos
}

public typealias FilesScreenProductEntryCompletion = @MainActor (
    Result<[URL], any Error>
) -> Void

public typealias FilesScreenProductEntryRequest = @MainActor (
    FilesScreenProductEntry,
    @escaping FilesScreenProductEntryCompletion
) -> Void

public enum FilesScreenModalEvent {
    case sourceConnectionPresented(dismiss: @MainActor () -> Void)
    case sourceConnectionDismissed
}

public enum FilesScreenSourceConnectionInteraction: String, Equatable, Sendable {
    case cancel
    case name
    case address
    case username
    case password
    case guest
    case connect
}

public enum FilesScreenMultiSelectionInteraction: String, Equatable, Sendable {
    case confirmDelete
    case delete
    case done
    case move
}

public enum FilesScreenFileBrowserErrorInteraction: String, Equatable, Sendable {
    case primary
    case secondary
}

public enum FilesScreenNavigationDirection: String, Equatable, Sendable {
    case back
    case forward
}

public enum FilesScreenBreadcrumbKind: String, Equatable, Sendable {
    case mediaLibrary
    case files
}

public enum FilesScreenManageAction: String, CaseIterable, Equatable, Sendable {
    case addFiles
    case addPhotos
    case addFolder
    case newFolder
    case selectMultiple

    var title: String {
        switch self {
        case .addFiles: "Add Files"
        case .addPhotos: "Add from Photos"
        case .addFolder: "Add Folder"
        case .newFolder: "New Library Folder"
        case .selectMultiple: "Select Multiple"
        }
    }
}

public enum FilesScreenScrollLayout: String, Equatable, Sendable {
    case grid
    case list
}

public enum FilesScreenReachabilityAction: Equatable, Sendable {
    case newFolderNameChanged
    case renameFolderNameChanged
    case sourceConnection(
        SourceConnectionKind,
        FilesScreenSourceConnectionInteraction
    )
    case newFolderCreate
    case newFolderCancel
    case renameFolderConfirm
    case renameFolderCancel
    case multiSelection(FilesScreenMultiSelectionInteraction)
    case fileBrowserError(FilesScreenFileBrowserErrorInteraction)
    case mediaLibraryErrorDismiss
    case sidebarSelect(String)
    case sidebarAddSource(SourceConnectionKind)
    case sidebarAddFolder
    case sidebarRefresh
    case sourceSidebar(String)
    case navigate(FilesScreenNavigationDirection)
    case search
    case breadcrumb(FilesScreenBreadcrumbKind)
    case manageOpened
    case manage(FilesScreenManageAction)
    case remoteFolder
    case remoteVideo
    case libraryFolder
    case libraryVideo
    case sidebarToggle
    case viewMode
    case sort
    case libraryReferenceMove

    public var probeName: String {
        switch self {
        case .newFolderNameChanged:
            "newFolder.name"
        case .renameFolderNameChanged:
            "renameFolder.name"
        case .sourceConnection(let kind, let interaction):
            "sourceConnection.\(kind.rawValue).\(interaction.rawValue)"
        case .newFolderCreate:
            "newFolder.create"
        case .newFolderCancel:
            "newFolder.cancel"
        case .renameFolderConfirm:
            "renameFolder.confirm"
        case .renameFolderCancel:
            "renameFolder.cancel"
        case .multiSelection(let interaction):
            "multiSelect.\(interaction.rawValue)"
        case .fileBrowserError(let interaction):
            "fileBrowserError.\(interaction.rawValue)"
        case .mediaLibraryErrorDismiss:
            "mediaLibraryError.dismiss"
        case .sidebarSelect(let id):
            "sidebar.select.\(id)"
        case .sidebarAddSource(let kind):
            "sidebar.add.\(kind.rawValue)"
        case .sidebarAddFolder:
            "sidebar.addFolder"
        case .sidebarRefresh:
            "sidebar.refresh"
        case .sourceSidebar(let action):
            "sourceSidebar.\(action)"
        case .navigate(let direction):
            "files.nav.\(direction.rawValue)"
        case .search:
            "files.search"
        case .breadcrumb(let kind):
            "breadcrumb.\(kind.rawValue)"
        case .manageOpened:
            "manage.open"
        case .manage(let action):
            "manage.\(action.rawValue)"
        case .remoteFolder:
            "remote.folder"
        case .remoteVideo:
            "remote.video"
        case .libraryFolder:
            "library.folder"
        case .libraryVideo:
            "library.video"
        case .sidebarToggle:
            "files.sidebarToggle"
        case .viewMode:
            "files.viewMode"
        case .sort:
            "files.sort"
        case .libraryReferenceMove:
            "libraryReference.move"
        }
    }
}

public enum FilesScreenReachabilityEvent: Equatable, Sendable {
    case action(FilesScreenReachabilityAction)
    case scroll(layout: FilesScreenScrollLayout, offset: Double)
    case libraryTap(name: String, selectionActive: Bool)
}

@MainActor
public struct FilesScreenInputs {
    let onModalEvent: (FilesScreenModalEvent) -> Void
    let requestProductEntry: FilesScreenProductEntryRequest
    let onReachabilityEvent: (FilesScreenReachabilityEvent) -> Void

    public init(
        onModalEvent: @escaping (FilesScreenModalEvent) -> Void,
        requestProductEntry: @escaping FilesScreenProductEntryRequest,
        onReachabilityEvent: @escaping (FilesScreenReachabilityEvent) -> Void
    ) {
        self.onModalEvent = onModalEvent
        self.requestProductEntry = requestProductEntry
        self.onReachabilityEvent = onReachabilityEvent
    }
}

@MainActor
@Observable
public final class FilesScreenViewState {
    var sourceItems: [SidebarSourceItem] = []
    var presentedSourceConnection: SourceConnectionKind?
    var sourceConnectionDraft = SourceConnectionDraft()
    var sourceConnectionDraftKind: SourceConnectionKind?
    var isCreatingFolder = false
    var newFolderName = ""
    var folderToRename: FileBrowsingDomain.LibraryFolder?
    var renamedFolderName = ""
    var folderToRemove: FileBrowsingDomain.LibraryFolder?
    var mediaReferenceSelectionIsActive = false
    var selectedMediaReferenceIDs: Set<UUID> = []
    var isBatchRemoveConfirmationPresented = false

#if DEBUG
#endif

    public init() {}

#if DEBUG
    public func applyDebugAlertField(
        _ field: FilesScreenAlertField,
        value: String
    ) -> Bool {
        switch field {
        case .newFolderName:
            guard isCreatingFolder else { return false }
            newFolderName = value
        case .renameFolderName:
            guard folderToRename != nil else { return false }
            renamedFolderName = value
        }
        return true
    }

#endif
}
