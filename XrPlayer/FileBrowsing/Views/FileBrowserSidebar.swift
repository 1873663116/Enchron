import SwiftUI

/// Finder-style sidebar for the file browser NavigationSplitView.
/// Shows data source sections (Local + saved remotes) and a storage bar for local storage.
struct FileBrowserSidebar: View {

    /// Hashable selection model bridging List(selection:) with the existing
    /// `activeDataSource: DataSource?` ViewModel state.
    enum SidebarItem: Hashable {
        case local
        case remote(UUID)
    }

    @Environment(FileBrowsingViewModel.self) private var viewModel

    // MARK: - Local storage capacity

    @State private var localStorageUsed: Int64 = 0
    @State private var localStorageTotal: Int64 = 0
    @State private var sidebarSelection: SidebarItem? = .local

    var body: some View {
        List(selection: $sidebarSelection) {
            Section("Sources") {
                localStorageRow
                    .tag(SidebarItem.local)
                    .accessibilitySortPriority(1000)

                ForEach(Array(viewModel.savedDataSources.enumerated()), id: \.element.id) { index, ds in
                    remoteSourceRow(ds)
                        .tag(SidebarItem.remote(ds.id))
                        .accessibilitySortPriority(Double(999 - index))
                }
                .onDelete { offsets in
                    let idsToRemove = offsets.map { viewModel.savedDataSources[$0].id }
                    for id in idsToRemove {
                        viewModel.removeDataSource(id: id)
                    }
                }
            }
        }
        .navigationTitle("Sources")
        .task {
            // Sync initial selection from ViewModel
            if let active = viewModel.activeDataSource {
                sidebarSelection = .remote(active.id)
            }
            await loadLocalStorageCapacity()
        }
        .onChange(of: sidebarSelection) { _, newValue in
            guard let newValue else { return }
            switch newValue {
            case .local:
                Task { await viewModel.useDefaultFolder() }
            case .remote(let id):
                if let ds = viewModel.savedDataSources.first(where: { $0.id == id }) {
                    Task { await viewModel.connectToDataSource(ds) }
                }
            }
        }
        .onChange(of: viewModel.activeDataSource?.id) { _, activeID in
            if let activeID {
                sidebarSelection = .remote(activeID)
            } else {
                sidebarSelection = .local
            }
        }
    }

    // MARK: - Local Storage Row

    private var localStorageRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Local Storage", systemImage: "internaldrive")

            if localStorageTotal > 0 {
                storageBar
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Remote Source Row

    private func remoteSourceRow(_ ds: FileBrowsingDomain.DataSource) -> some View {
        HStack {
            Label(
                ds.name,
                systemImage: iconName(for: ds.sourceType)
            )

            Spacer()

            if viewModel.activeDataSource?.id == ds.id {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Connected")
            }
        }
    }

    // MARK: - Storage Bar

    private var storageBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(
                value: Double(localStorageUsed),
                total: Double(localStorageTotal)
            )
            .tint(storageBarColor)

            Text("\(formattedBytes(localStorageUsed)) of \(formattedBytes(localStorageTotal)) used")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private var storageBarColor: Color {
        let ratio = Double(localStorageUsed) / Double(max(localStorageTotal, 1))
        if ratio > 0.9 { return .red }
        if ratio > 0.75 { return .orange }
        return .accentColor
    }

    // MARK: - Helpers

    private func iconName(for sourceType: FileBrowsingDomain.SourceType) -> String {
        switch sourceType {
        case .smb:
            return "externaldrive.connected.to.line.below"
        case .webDAV:
            return "network"
        case .local, .photoLibrary:
            return "folder"
        }
    }

    private func loadLocalStorageCapacity() async {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        do {
            let values = try documentsURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])
            let available = values.volumeAvailableCapacityForImportantUsage ?? 0
            let total = Int64(values.volumeTotalCapacity ?? 0)
            await MainActor.run {
                localStorageTotal = total
                localStorageUsed = total - available
            }
        } catch {
            print("[FileBrowserSidebar] Failed to read storage capacity: \(error)")
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
