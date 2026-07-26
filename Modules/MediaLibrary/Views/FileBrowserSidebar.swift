import DesignSystem
import MediaLibrary
import SwiftUI

/// Finder-style sidebar for the file browser NavigationSplitView.
/// Shows data sources (Local + saved remotes) with a storage bar pinned to the bottom.
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
        VStack(spacing: 0) {
            List(selection: $sidebarSelection) {
                // Single section, no header — the navigation title "Sources" serves as the header.
                Section {
                    localSourceRow
                        .tag(SidebarItem.local)
                        .accessibilityIdentifier("FileBrowsing-Sidebar-row-local")
                        .accessibilityLabel("Local Storage")
                        .accessibilitySortPriority(1000)

                    ForEach(Array(viewModel.savedDataSources.enumerated()), id: \.element.id) { index, ds in
                        remoteSourceRow(ds)
                            .tag(SidebarItem.remote(ds.id))
                            .accessibilityIdentifier("FileBrowsing-Sidebar-row-\(ds.id)")
                            .accessibilityLabel(ds.name)
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

            // Storage bar pinned to sidebar bottom
            if localStorageTotal > 0 {
                storageFooter
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
        .task {
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

    // MARK: - Source Rows (compact, like HTML reference)

    /// Local storage: icon + name + green dot when selected.
    private var localSourceRow: some View {
        HStack {
            Label("Local Storage", systemImage: "internaldrive")
            Spacer()
            if sidebarSelection == .local {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
        }
    }

    /// Remote source: icon + name + status dot.
    private func remoteSourceRow(_ ds: FileBrowsingDomain.DataSource) -> some View {
        HStack {
            Label(
                ds.name,
                systemImage: iconName(for: ds.sourceType)
            )
            Spacer()
            Circle()
                .fill(viewModel.activeDataSource?.id == ds.id ? .green : .secondary.opacity(0.3))
                .frame(width: 8, height: 8)
                .accessibilityLabel(viewModel.activeDataSource?.id == ds.id ? "Connected" : "Disconnected")
        }
    }

    // MARK: - Storage Footer

    /// Bottom-pinned storage indicator: "Storage    X.X GB / Y GB" + progress bar.
    private var storageFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Storage")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(formattedBytes(localStorageUsed)) / \(formattedBytes(localStorageTotal))")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }

            ProgressView(
                value: Double(localStorageUsed),
                total: Double(localStorageTotal)
            )
            .tint(storageBarColor)
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
