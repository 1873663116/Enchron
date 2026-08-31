import Foundation
import MediaLibrary
import Observation
import PhotosUI
import Playback
import SwiftUI
import UniformTypeIdentifiers

#if DEBUG
import DesignSystem

@MainActor
final class FileBrowserReachabilityErrorRequest {
    let message: String
    private(set) var wasHandled = false

    init(message: String) {
        self.message = message
    }

    func handle(show: (String) -> Void) {
        guard wasHandled == false else { return }
        show(message)
        wasHandled = true
    }
}

@MainActor
final class FileBrowserAlertFieldRequest {
    enum Field: String {
        case newFolderName
        case renameFolderName
    }

    let field: Field
    let value: String
    private(set) var wasHandled = false

    init(field: Field, value: String) {
        self.field = field
        self.value = value
    }

    func handle(
        field expectedField: Field,
        isPresented: Bool,
        binding: Binding<String>
    ) {
        handle { field, value in
            guard field == expectedField, isPresented else { return false }
            binding.wrappedValue = value
            return true
        }
    }

    func handle(
        apply: (Field, String) -> Bool
    ) {
        guard wasHandled == false, apply(field, value) else { return }
        wasHandled = true
    }
}

extension Notification.Name {
    static let fileBrowserReachabilityError = Notification.Name(
        "app.enchron.debug.file-browser-reachability-error"
    )
    static let fileBrowserAlertField = Notification.Name(
        "app.enchron.debug.file-browser-alert-field"
    )
}
#endif

@MainActor
@Observable
final class FilesScreenFileImportCoordinator {
    var isPresented = false
    private(set) var kind = FilesScreenFileImportKind.mediaFiles
    @ObservationIgnored private var completion: FilesScreenProductEntryCompletion?
#if DEBUG
    @ObservationIgnored private var diagnosticRequestID: UUID?
#endif

    func present(
        kind: FilesScreenFileImportKind,
        completion: @escaping FilesScreenProductEntryCompletion
    ) {
        self.kind = kind
        self.completion = completion
#if DEBUG
        if let diagnosticRequestID {
            SystemImportDeliveryDiagnostics.discardRequest(diagnosticRequestID)
        }
        diagnosticRequestID = kind == .mediaFiles
            ? SystemImportDeliveryDiagnostics.beginRequest(
                deliveryDomain: .filesProviderSecurityScope
            )
            : nil
#endif
        isPresented = true
    }

    func deliver(_ result: Result<[URL], any Error>) {
        isPresented = false
        let completion = completion
        self.completion = nil
#if DEBUG
        if let diagnosticRequestID {
            switch result {
            case .success(let urls):
                SystemImportDeliveryDiagnostics.recordFileImporterCompletion(
                    requestID: diagnosticRequestID,
                    deliveredURLs: urls
                )
            case .failure:
                SystemImportDeliveryDiagnostics.discardRequest(diagnosticRequestID)
            }
            self.diagnosticRequestID = nil
        }
#endif
        completion?(result)
    }
}

@MainActor
@Observable
final class FilesScreenPhotosImportCoordinator {
    typealias Loader = @Sendable (PhotosPickerItem) async throws -> AppManagedMediaFile?

    var isPresented = false
    var selection: PhotosPickerItem?
    @ObservationIgnored private var completion: FilesScreenProductEntryCompletion?
    private let loader: Loader
#if DEBUG
    @ObservationIgnored private var diagnosticRequestID: UUID?
#endif

    init(
        loader: @escaping Loader = { item in
            try await item.loadTransferable(type: AppManagedMediaFile.self)
        }
    ) {
        self.loader = loader
    }

    func present(
        completion: @escaping FilesScreenProductEntryCompletion
    ) {
        selection = nil
        self.completion = completion
#if DEBUG
        if let diagnosticRequestID {
            SystemImportDeliveryDiagnostics.discardRequest(diagnosticRequestID)
        }
        diagnosticRequestID = SystemImportDeliveryDiagnostics.beginRequest(
            deliveryDomain: .appManagedPhotoTransfer
        )
#endif
        isPresented = true
    }

    func deliverSelection() async {
        guard let selection, let completion else { return }
        let assetIdentifier = selection.itemIdentifier
        self.selection = nil
        self.completion = nil
        isPresented = false

        do {
            guard let importedFile = try await loader(selection) else {
#if DEBUG
                if let diagnosticRequestID {
                    SystemImportDeliveryDiagnostics.discardRequest(diagnosticRequestID)
                    self.diagnosticRequestID = nil
                }
#endif
                completion(.failure(ManagedMediaImportError.transferUnavailable))
                return
            }
#if DEBUG
            if let diagnosticRequestID {
                SystemImportDeliveryDiagnostics.recordPhotosTransferCompletion(
                    requestID: diagnosticRequestID,
                    assetIdentifier: assetIdentifier,
                    deliveredURL: importedFile.url
                )
                self.diagnosticRequestID = nil
            }
#endif
            completion(.success([importedFile.url]))
        } catch is CancellationError {
#if DEBUG
            if let diagnosticRequestID {
                SystemImportDeliveryDiagnostics.discardRequest(diagnosticRequestID)
                self.diagnosticRequestID = nil
            }
#endif
            return
        } catch {
#if DEBUG
            if let diagnosticRequestID {
                SystemImportDeliveryDiagnostics.discardRequest(diagnosticRequestID)
                self.diagnosticRequestID = nil
            }
#endif
            completion(.failure(error))
        }
    }
}

struct FilesScreenHost: View {
    @Environment(AppModalPresentationCoordinator.self)
    private var modalPresentationCoordinator

#if DEBUG
    @Environment(FileBrowsingViewModel.self) private var fileBrowser
#endif

    @State private var screenState = FilesScreenViewState()
    @State private var fileImportCoordinator = FilesScreenFileImportCoordinator()
    @State private var photosImportCoordinator = FilesScreenPhotosImportCoordinator()

    var body: some View {
        MediaLibrary.FilesScreen(
            state: screenState,
            inputs: FilesScreenInputs(
                onModalEvent: deliverModalEvent,
                requestProductEntry: requestProductEntry,
                onReachabilityEvent: recordReachability
            )
        )
        .fileImporter(
            isPresented: $fileImportCoordinator.isPresented,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: fileImportCoordinator.kind == .mediaFiles,
            onCompletion: fileImportCoordinator.deliver
        )
        .photosPicker(
            isPresented: $photosImportCoordinator.isPresented,
            selection: $photosImportCoordinator.selection,
            matching: .videos,
            preferredItemEncoding: .current
        )
        .onChange(of: photosImportCoordinator.selection) { _, selection in
            guard selection != nil else { return }
            Task { await photosImportCoordinator.deliverSelection() }
        }
#if DEBUG
        .onReceive(
            NotificationCenter.default.publisher(for: .fileBrowserReachabilityError)
        ) { notification in
            guard let request = notification.object as? FileBrowserReachabilityErrorRequest else {
                return
            }
            request.handle { fileBrowser.lastErrorMessage = $0 }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .fileBrowserAlertField)
        ) { notification in
            guard let request = notification.object as? FileBrowserAlertFieldRequest else {
                return
            }
            request.handle { field, value in
                let target: FilesScreenAlertField = switch field {
                case .newFolderName: .newFolderName
                case .renameFolderName: .renameFolderName
                }
                let wasApplied = screenState.applyDebugAlertField(
                    target,
                    value: value
                )
                if wasApplied {
                    let action: FilesScreenReachabilityAction = switch target {
                    case .newFolderName: .newFolderNameChanged
                    case .renameFolderName: .renameFolderNameChanged
                    }
                    recordReachability(.action(action))
                }
                return wasApplied
            }
        }
#endif
    }

    private var allowedContentTypes: [UTType] {
        switch fileImportCoordinator.kind {
        case .folder:
            [.folder]
        case .mediaFiles:
            FileBrowsingDomain.MediaDiscoveryAdmissionPolicy.mediaFiles
                .allowedExtensions
                .sorted()
                .compactMap { UTType(filenameExtension: $0) }
        }
    }

    private func deliverModalEvent(_ event: FilesScreenModalEvent) {
        switch event {
        case .sourceConnectionPresented(let dismiss):
            modalPresentationCoordinator.modalDidPresent(
                .sourceConnection,
                dismiss: dismiss
            )
        case .sourceConnectionDismissed:
            modalPresentationCoordinator.modalDidDismiss(.sourceConnection)
        }
    }

    private func requestProductEntry(
        _ entry: FilesScreenProductEntry,
        completion: @escaping FilesScreenProductEntryCompletion
    ) {
        switch entry {
        case .fileImporter(let kind):
            fileImportCoordinator.present(kind: kind, completion: completion)
        case .photos:
            Task {
                await modalPresentationCoordinator
                    .dismissPresentedModalBeforePresentingNext()
                photosImportCoordinator.present(completion: completion)
            }
        }
    }

    private func recordReachability(_ event: FilesScreenReachabilityEvent) {
        switch event {
        case .action(let action):
#if DEBUG
            SurfaceInputProbes.record(
                "reachability files delivered action=\(action.probeName)",
                retention: .evidence
            )
#endif
        case .scroll(let layout, let offset):
#if DEBUG
            SurfaceInputProbes.record(
                "reachability fileScroll kind=\(layout.rawValue) offset=\(offset)",
                retention: .evidence
            )
#endif
        case .libraryTap(let name, let selectionActive):
            SurfaceInputProbes.record(
                "libraryTap name=\(name) selectionActive=\(selectionActive)"
            )
        }
    }
}
