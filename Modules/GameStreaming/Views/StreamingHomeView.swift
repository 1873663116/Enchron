import DesignSystem
import Playback
import SwiftUI

public struct StreamingHomeView: View {
    @Environment(StreamingModel.self) private var model
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @State private var isAddingHost = false
    @State private var isConfirmingRemoval = false
    @State private var pendingRemovalHostID: HostID?
    @State private var isSidebarVisible = true

    public init() {}

    private var launchFailure: (hostID: HostID, failure: StreamFailure)? {
        for host in model.hosts {
            guard let failure = model.failure(for: host.id), failure.stage == .launch else {
                continue
            }
            return (host.id, failure)
        }
        return nil
    }

    private func dismissLaunchFailure() {
        guard let launchFailure else { return }
        model.clearFailure(hostID: launchFailure.hostID)
    }

    public var body: some View {
        SidebarSplitLayout(
            sidebarIsVisible: model.emptyStateVisible == false && isSidebarVisible
        ) {
            sidebar
        } content: {
            contentColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .alert(
            "无法建立串流",
            isPresented: Binding(
                get: { launchFailure != nil },
                set: { presented in
                    if presented == false { dismissLaunchFailure() }
                }
            ),
            presenting: launchFailure
        ) { _ in
            Button("确认") { dismissLaunchFailure() }
        } message: { item in
            Text(item.failure.message)
        }
        .onAppear { model.refreshReachability() }
        .task {
            if model.selectedHostID == nil, let firstHostID = model.hosts.first?.id {
                model.selectHost(firstHostID)
            }
        }
        .sheet(isPresented: $isAddingHost) {
            StreamAddHostView()
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        if model.emptyStateVisible {
            emptyState
        } else if let host = model.selectedHost {
            if host.pairing.isPaired {
                hostDetail(host)
            } else {
                StreamPairingView(hostID: host.id)
            }
        } else {
            Text("从左侧选择主机")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.Surface.supportingText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer(minLength: 0)
            Image(systemName: "desktopcomputer")
                .font(DesignTokens.SymbolSize.giant)
                .foregroundStyle(DesignTokens.Surface.supportingText)
            Text("还没有主机")
                .font(DesignTokens.Typography.title)
            Text("添加同一网络内的主机，配对后从它的应用入口开始串流。")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.Surface.supportingText)
                .multilineTextAlignment(.center)
            GlassCapsuleIconLabelButton(
                title: "添加主机",
                systemName: "plus",
                accessibilityLabel: "添加主机",
                action: { isAddingHost = true },
                accessibilityIdentifier: "Stream-AddHost-entry"
            )
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Stream-EmptyState")
    }

    private var sidebar: some View {
        StreamHostSidebar(
            hosts: model.hosts,
            selectedHostID: model.selectedHostID,
            onAdd: { isAddingHost = true },
            onSelect: { model.selectHost($0.id) },
            onRemove: { host in
                pendingRemovalHostID = host.id
                isConfirmingRemoval = true
            }
        )
    }

    private func hostDetail(_ host: HostSnapshot) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
            HStack(spacing: DesignTokens.Spacing.lg) {
                SidebarToggleButton(
                    isVisible: $isSidebarVisible,
                    accessibilityIdentifier: "Stream-Sidebar-Toggle"
                )
                Text(host.name)
                    .font(DesignTokens.Typography.title)
                    .lineLimit(1)
                    .accessibilityIdentifier("Stream-HostDetail-name")
                    .accessibilityValue(host.name)
                Spacer(minLength: 0)
            }

            failureLine(host)

            StreamAppGridView(
                state: host.applications,
                artworkURL: { appID in
                    model.artworkCache["\(host.id.rawValue)-\(appID.rawValue)"]
                },
                hiddenAppIDs: model.hiddenApplicationIDs(hostID: host.id),
                onLaunch: { application in
                    launch(host, application)
                },
                onRemove: { application in
                    model.hideApplication(hostID: host.id, appID: application.id)
                }
            )
            .task(id: host.applications) {
                for application in host.applications.applications ?? [] {
                    _ = await model.artworkFileURL(hostID: host.id, appID: application.id)
                }
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Stream-HostDetail")
        .enchronDestructiveConfirmation(
            "移除主机？",
            message: "移除后可以重新添加该主机。主机上正在运行的游戏不会退出。",
            confirmTitle: "移除",
            isPresented: $isConfirmingRemoval
        ) {
            if let pendingRemovalHostID,
               let target = model.hosts.first(where: { $0.id == pendingRemovalHostID }) {
                forget(target)
            }
            pendingRemovalHostID = nil
        }
    }

    @ViewBuilder
    private func failureLine(_ host: HostSnapshot) -> some View {
        Group {
            if let failure = model.failure(for: host.id) {
                Text(failure.message)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.SourceConnection.failureColor)
                    .accessibilityIdentifier("Stream-HostDetail-error")
                    .accessibilityValue(failure.readableValue)
            }
        }
    }

    private func forget(_ host: HostSnapshot) {
        do {
            try model.forgetHost(host.id)
        } catch let failure as StreamFailure {
            model.recordFailure(failure, hostID: host.id)
        } catch {
            model.recordFailure(
                StreamFailure(
                    stage: .teardown,
                    kind: .unknown,
                    message: "移除主机失败",
                    recovery: .none
                ),
                hostID: host.id
            )
        }
    }

    private func launch(_ host: HostSnapshot, _ application: HostApplication) {
        model.clearFailure(hostID: host.id)
        guard playbackRuntime.currentLaunchRequest == nil else {
            model.recordFailure(
                StreamFailure(
                    stage: .launch,
                    kind: .unknown,
                    message: "播放窗口正在播放媒体文件，先结束播放再开始串流",
                    recovery: .retry
                ),
                hostID: host.id
            )
            return
        }
        Task {
            do {
                try await model.launch(
                    hostID: host.id,
                    appID: application.id,
                    appName: application.name
                )
            } catch let failure as StreamFailure {
                model.recordFailure(failure, hostID: host.id)
            } catch {
                model.recordFailure(
                    StreamFailure(
                        stage: .launch,
                        kind: .unknown,
                        message: "启动串流失败",
                        recovery: .retry
                    ),
                    hostID: host.id
                )
            }
        }
    }
}

private struct StreamHostSidebar: View {
    let hosts: [HostSnapshot]
    let selectedHostID: HostID?
    let onAdd: () -> Void
    let onSelect: (HostSnapshot) -> Void
    let onRemove: (HostSnapshot) -> Void
    @State private var expandedHostID: HostID?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.SourceSidebar.headerContentGap) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text("主机")
                        .font(DesignTokens.SourceSidebar.sectionTitleFont)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                    CircleIconButton(
                        systemName: "plus",
                        accessibilityLabel: String(localized: "添加主机"),
                        action: onAdd,
                        accessibilityIdentifier: "Stream-HostSidebar-addButton"
                    )
                }
                .padding(.horizontal, DesignTokens.SourceSidebar.contentPaddingH)

                VStack(spacing: DesignTokens.SourceSidebar.rowSpacing) {
                    ForEach(hosts) { host in
                        row(host)
                    }
                }
                .padding(.horizontal, DesignTokens.SourceSidebar.listPaddingH)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignTokens.SourceSidebar.contentPaddingV)
        .frame(width: DesignTokens.SourceSidebar.width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .enchronSidebarSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Stream-HostSidebar")
    }

    private func row(_ host: HostSnapshot) -> some View {
        EditableSourceSidebarRow(
            icon: "desktopcomputer",
            title: host.name,
            isSelected: host.id == selectedHostID,
            isEnabled: true,
            isActiveSource: false,
            isDeletable: true,
            isSelectionMode: false,
            isChecked: false,
            isAppearing: false,
            isSwipeExpanded: expandedHostID == host.id,
            isDragging: false,
            rowOffset: 0,
            allowsReordering: false,
            allowsSwipe: true,
            statusColor: color(for: host.statusLight),
            onTap: { onSelect(host) },
            onToggleSelection: {},
            onSwipeBegan: { expandedHostID = nil },
            onSwipeExpanded: { expandedHostID = host.id },
            onSwipeCollapsed: { expandedHostID = nil },
            onDelete: { onRemove(host) },
            onReorderBegan: {},
            onReorderChanged: { _ in },
            onReorderEnded: {}
        )
        .accessibilityLabel(host.name)
        .accessibilityValue(host.readableStatus)
        .accessibilityAddTraits(host.id == selectedHostID ? .isSelected : [])
        .accessibilityIdentifier("Stream-HostRow-\(host.name)")
    }

    private func color(for light: HostStatusLight) -> Color {
        switch light {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }
}
