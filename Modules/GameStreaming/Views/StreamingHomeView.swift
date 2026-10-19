import DesignSystem
import Playback
import SwiftUI

public struct StreamingHomeView: View {
    @Environment(StreamingModel.self) private var model
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @State private var isAddingHost = false
    @State private var isConfirmingRemoval = false
    @State private var isPresentingHostActions = false
    @State private var pendingRemovalHostID: HostID?

    public init() {}

    public var body: some View {
        SidebarSplitLayout(sidebarIsVisible: model.emptyStateVisible == false) {
            sidebar
        } content: {
            contentColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Button {
                    isPresentingHostActions = true
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text(host.name)
                            .font(DesignTokens.Typography.title)
                            .lineLimit(1)
                        Image(systemName: "ellipsis.circle")
                            .font(DesignTokens.SymbolSize.label)
                            .foregroundStyle(DesignTokens.Surface.supportingText)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("主机操作")
                .accessibilityValue(host.name)
                .accessibilityIdentifier("Stream-HostActions-button")
                Text(host.address.displayString)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.supportingText)
                    .accessibilityIdentifier("Stream-HostDetail-address")
                    .accessibilityValue(host.address.displayString)
                Text(pairingSummary(host.pairing))
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.supportingText)
                    .accessibilityIdentifier("Stream-HostDetail-pairing")
                    .accessibilityValue("pairing=\(host.pairing.readableValue)")
            }

            remoteSessionLine(host)

            failureLine(host)

            StreamAppGridView(
                state: host.applications,
                artworkURL: { appID in
                    model.artworkCache["\(host.id.rawValue)-\(appID.rawValue)"]
                },
                hiddenAppIDs: model.hiddenApplicationIDs(hostID: host.id)
            ) { application in
                launch(host, application)
            } onRemove: { application in
                model.hideApplication(hostID: host.id, appID: application.id)
            }
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
        .confirmationDialog(
            host.name,
            isPresented: $isPresentingHostActions,
            titleVisibility: .visible
        ) {
            if host.pairing.isPaired {
                Button("查看全部应用") {
                    model.selectHost(host.id)
                }
                .accessibilityIdentifier("Stream-HostActions-viewApps")
            }
            Button("移除主机", role: .destructive) {
                isConfirmingRemoval = true
            }
            .accessibilityIdentifier("Stream-HostActions-remove")
            Button("取消", role: .cancel) {}
        } message: {
            Text(host.address.displayString)
        }
        .enchronDestructiveConfirmation(
            "移除主机？",
            message: "移除后可以重新添加该主机。主机上正在运行的游戏不会退出。",
            confirmTitle: "移除",
            isPresented: $isConfirmingRemoval
        ) {
            if let pendingRemovalHostID,
               let target = model.hosts.first(where: { $0.id == pendingRemovalHostID }) {
                forget(target)
            } else {
                forget(host)
            }
            pendingRemovalHostID = nil
        }
    }

    @ViewBuilder
    private func remoteSessionLine(_ host: HostSnapshot) -> some View {
        if let session = host.remoteSession, session.isBusy {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("主机正在运行：\(runningApplicationName(session, host: host))")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.supportingText)
                    .accessibilityIdentifier("Stream-HostDetail-remoteSession")
                    .accessibilityValue(
                        "busy=true;game=\(session.currentGame ?? "none")"
                    )
            }
        }
    }

    private func runningApplicationName(
        _ session: RemoteSessionInfo,
        host: HostSnapshot
    ) -> String {
        guard let identifier = session.currentGame else { return host.name }
        if let applications = host.applications.applications,
           let matched = applications.first(where: { $0.id.rawValue == identifier }) {
            return matched.name
        }
        return identifier
    }

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

    private func pairingSummary(_ pairing: PairingState) -> String {
        switch pairing {
        case .unknown: "配对状态未知"
        case .unpaired: "未配对"
        case .paired: "已配对"
        case .failed: "配对失败"
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
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .frame(
                                width: DesignTokens.Interactive.large,
                                height: DesignTokens.Interactive.large
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加主机")
                    .accessibilityIdentifier("Stream-HostSidebar-addButton")
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
            isDeletable: false,
            isSelectionMode: false,
            isChecked: false,
            isAppearing: false,
            isSwipeExpanded: expandedHostID == host.id,
            isDragging: false,
            rowOffset: 0,
            allowsReordering: false,
            allowsSwipe: true,
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
        .overlay(alignment: .trailing) {
            statusLight(host.statusLight)
                .padding(.trailing, DesignTokens.SourceSidebar.listPaddingH)
                .allowsHitTesting(false)
        }
        .accessibilityLabel(host.name)
        .accessibilityValue(host.readableStatus)
        .accessibilityAddTraits(host.id == selectedHostID ? .isSelected : [])
        .accessibilityIdentifier("Stream-HostRow-\(host.name)")
    }

    private func statusLight(_ light: HostStatusLight) -> some View {
        Circle()
            .fill(color(for: light))
            .frame(
                width: DesignTokens.Interactive.statusDotSize,
                height: DesignTokens.Interactive.statusDotSize
            )
    }

    private func color(for light: HostStatusLight) -> Color {
        switch light {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }
}
