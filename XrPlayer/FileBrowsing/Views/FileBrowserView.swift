import SwiftUI

public struct FileBrowserView: View {
    @Environment(FileBrowsingViewModel.self) private var viewModel

    public init() {}
    
    public var body: some View {
        NavigationStack {
            FolderListView(
                files: viewModel.files,
                isLoading: viewModel.isLoading,
                onFileSelected: { file in
                    viewModel.selectFile(file)
                }
            )
            .navigationTitle("Files")
            .onAppear {
                Task {
                    await viewModel.loadFiles()
                }
            }
            .refreshable {
                await viewModel.loadFiles()
            }
        }
    }
}
