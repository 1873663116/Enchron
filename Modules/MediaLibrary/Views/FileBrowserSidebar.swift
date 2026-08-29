import DesignSystem
import MediaLibrary
import SwiftUI

struct FileBrowserSidebar: View {

    enum SidebarItem: Hashable {
        case local
        case remote(UUID)
    }

    @Environment(FileBrowsingViewModel.self) private var viewModel

    @State private var localStorageUsed: Int64 = 0
    @State private var localStorageTotal: Int64 = 0
    @State private var sidebarSelection: SidebarItem? = .local

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $sidebarSelection) {
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
                    Task {
                        let result = await viewModel.connectToDataSource(ds)
                        if case .failed(let failure) = result,
                           viewModel.activeDataSource?.id == ds.id {
                            viewModel.lastErrorMessage = failure.sourceConnectionMessage
                        }
                    }
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

    private func iconName(for sourceType: FileBrowsingDomain.SourceType) -> String {
        sourceType.connectionIcon
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
