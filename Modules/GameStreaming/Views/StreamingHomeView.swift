import DesignSystem
import SwiftUI

public struct StreamingHomeView: View {
    private enum Route: Hashable {
        case addHost
        case pairing(HostID)
    }

    @Environment(StreamingModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var route: [Route] = []
    @State private var launchFailureText: String?
    @State private var removalFailureText: String?
    @State private var isConfirmingRemoval = false

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
        .onChange(of: model.pairing?.state) { _, state in
            guard let state else { return }
            switch state {
            case .unpaired:
                guard route.isEmpty, let hostID = model.selectedHostID else { return }
                route.append(.pairing(hostID))
            case .paired:
                guard let hostID = model.selectedHostID ?? model.hosts.first?.id else { return }
                model.loadApplications(hostID: hostID)
            case .unknown, .failed:
                break
            }
        }
        .onChange(of: model.session?.id) { _, sessionID in
            // Presenting the session is the session's own effect, so a launch
            // that did not come from a tapped card also puts its window up.
            if sessionID != nil {
                openWindow(id: "streaming")
            }
        }
        .task {
            if model.selectedHostID == nil, let firstHostID = model.hosts.first?.id {
                model.selectHost(firstHostID)
            }
        }
    }

    private var contentColumn: some View {
        NavigationStack(path: $route) {
            detailColumn
                .navigationDestination(for: Route.self) { destination in
                    switch destination {
                    case .addHost:
                        StreamAddHostView()
                    case .pairing(let hostID):
                        StreamPairingView(hostID: hostID)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailColumn: some View {
        if model.emptyStateVisible {
            emptyState
        } else if let host = model.selectedHost {
            hostDetail(host)
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
                action: { route.append(.addHost) },
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
            onAdd: { route.append(.addHost) },
            onSelect: select
        )
    }

    private func select(_ host: HostSnapshot) {
        model.selectHost(host.id)
        launchFailureText = nil
        removalFailureText = nil
        guard host.pairing.isPaired == false, route.isEmpty else { return }
        route.append(.pairing(host.id))
    }

    private func hostDetail(_ host: HostSnapshot) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(host.name)
                    .font(DesignTokens.Typography.title)
                    .lineLimit(1)
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

            HStack(spacing: DesignTokens.Interactive.buttonSpacing) {
                if host.pairing.isPaired == false {
                    Button {
                        route.append(.pairing(host.id))
                    } label: {
                        Label("配对", systemImage: "link.badge.plus")
                    }
                    .accessibilityIdentifier("Stream-HostDetail-pairButton")
                }
                Button(role: .destructive) {
                    isConfirmingRemoval = true
                } label: {
                    Label("移除主机", systemImage: "trash")
                }
                .accessibilityIdentifier("Stream-HostDetail-removeButton")
            }

            if let removalFailureText {
                Text(removalFailureText)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.SourceConnection.failureColor)
            }

            if let launchFailureText {
                Text(launchFailureText)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.SourceConnection.failureColor)
            }

            StreamAppGridView(state: host.applications) { application in
                launch(host, application)
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
            forget(host)
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
            removalFailureText = nil
        } catch let failure as StreamFailure {
            removalFailureText = failure.message
        } catch {
            removalFailureText = "移除主机失败"
        }
    }

    private func launch(_ host: HostSnapshot, _ application: HostApplication) {
        launchFailureText = nil
        Task {
            do {
                try await model.launch(
                    hostID: host.id,
                    appID: application.id,
                    appName: application.name
                )
                openWindow(id: "streaming")
            } catch let failure as StreamFailure {
                launchFailureText = failure.message
            } catch {
                launchFailureText = "启动串流失败"
            }
        }
    }
}

private struct StreamHostSidebar: View {
    let hosts: [HostSnapshot]
    let selectedHostID: HostID?
    let onAdd: () -> Void
    let onSelect: (HostSnapshot) -> Void

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
            isSwipeExpanded: false,
            isDragging: false,
            rowOffset: 0,
            allowsReordering: false,
            allowsSwipe: false,
            onTap: { onSelect(host) }
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
