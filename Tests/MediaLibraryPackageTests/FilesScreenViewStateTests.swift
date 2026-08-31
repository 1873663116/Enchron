import Foundation
import Testing
@testable import MediaLibrary

@MainActor
struct FilesScreenViewStateTests {
    @Test("debug alert fields only update the matching presented alert")
    func alertFieldDeliveryRequiresItsPresentation() {
        let state = FilesScreenViewState()

        #expect(
            state.applyDebugAlertField(.newFolderName, value: "Hidden") == false
        )
        #expect(state.newFolderName.isEmpty)

        state.isCreatingFolder = true

        #expect(
            state.applyDebugAlertField(.newFolderName, value: "Visible")
        )
        #expect(state.newFolderName == "Visible")
        #expect(
            state.applyDebugAlertField(.renameFolderName, value: "Wrong") == false
        )
        #expect(state.renamedFolderName.isEmpty)
    }

    @Test("product entry keeps Photos distinct from file imports")
    func productEntryDomainIncludesPhotosWithoutConflatingFileImports() {
        #expect(
            FilesScreenProductEntry.fileImporter(.mediaFiles)
                != .fileImporter(.folder)
        )
        #expect(
            FilesScreenProductEntry.photos
                != .fileImporter(.mediaFiles)
        )
        #expect(FilesScreenManageAction.addPhotos.title == "Add from Photos")
        #expect(
            FilesScreenReachabilityAction.manage(.addPhotos).probeName
                == "manage.addPhotos"
        )
    }

    @Test("file imports preserve the addFiles and addFolder domain boundary")
    func fileImportActionsRemainCausal() {
        let first = URL(fileURLWithPath: "/tmp/first.mkv")
        let second = URL(fileURLWithPath: "/tmp/second.mkv")

        #expect(
            FilesScreenFileImportKind.mediaFiles.action(for: [first, second])
                == .addFiles([first, second])
        )
        #expect(
            FilesScreenFileImportKind.folder.action(for: [first])
                == .addFolder(first)
        )
        #expect(
            FilesScreenFileImportKind.folder.action(for: [])
                == .addFiles([])
        )
    }

    @Test("folder removal copy describes reference reparenting")
    func folderRemovalConfirmationCopy() {
        #expect(
            FilesScreen.removeFolderConfirmation
                == "Remove this library folder and its subfolders? Their media references will move to the parent location. Original media will not be changed."
        )
    }

    @Test("reachability actions preserve existing probe names through typed cases")
    func typedReachabilityActionNames() {
        #expect(
            FilesScreenReachabilityAction.sourceConnection(
                .webDAV,
                .connect
            ).probeName == "sourceConnection.webDAV.connect"
        )
        #expect(
            FilesScreenReachabilityAction.manage(.selectMultiple).probeName
                == "manage.selectMultiple"
        )
        #expect(
            FilesScreenReachabilityAction.sidebarAddSource(.smb).probeName
                == "sidebar.add.smb"
        )
    }
}
