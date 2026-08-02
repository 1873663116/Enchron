import DesignSystem
import Foundation
import SwiftUI

public enum SourceConnectionKind: String, CaseIterable, Identifiable, Sendable {
    case smb
    case webDAV

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .smb: "SMB"
        case .webDAV: "WebDAV"
        }
    }

    public var sourceType: FileBrowsingDomain.SourceType {
        switch self {
        case .smb: .smb
        case .webDAV: .webDAV
        }
    }

    var subtitle: String {
        switch self {
        case .smb: "Local network share · Host name or IP address"
        case .webDAV: "HTTP(S) server · Full server address"
        }
    }

    var systemImage: String {
        switch self {
        case .smb: "externaldrive.connected.to.line.below"
        case .webDAV: "network"
        }
    }

    var addressLabel: String {
        switch self {
        case .smb: "Address"
        case .webDAV: "Server Address"
        }
    }

    var addressPlaceholder: String {
        switch self {
        case .smb: "192.168.1.20"
        case .webDAV: "https://server.example/dav/"
        }
    }
}

public struct SourceConnectionRequest: Sendable, Equatable {
    public let kind: SourceConnectionKind
    public let name: String
    public let address: String
    public let share: String
    public let username: String
    public let password: String
    public let connectsAsGuest: Bool

    public init(
        kind: SourceConnectionKind,
        name: String,
        address: String,
        share: String,
        username: String,
        password: String,
        connectsAsGuest: Bool
    ) {
        self.kind = kind
        self.name = name
        self.address = address
        self.share = share
        self.username = username
        self.password = password
        self.connectsAsGuest = connectsAsGuest
    }
}

public enum SourceConnectionOutcome: Sendable, Equatable {
    case connected
    case failed(message: String)
    case timedOut(message: String)
}

private struct ConnectionFormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    let accessibilityIdentifier: String

    @FocusState private var isFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: DesignTokens.Radius.small,
            style: .continuous
        )

        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(label)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Surface.supportingText)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(.primary)
            .focused($isFocused)
            .enchronLiteralTextInput()
            .enchronHoverEffectDisabled()
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(height: DesignTokens.Interactive.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(shape)
            .enchronGlassBackground(in: shape)
            .enchronHoverContentShape(shape)
            .enchronHoverEffect(.automatic)
            .contentShape(shape)
            .overlay {
                shape.strokeBorder(
                    isFocused ? DesignTokens.Surface.focusBorder : .clear,
                    lineWidth: DesignTokens.Stroke.bold
                )
                .animation(DesignTokens.AnimationToken.selection, value: isFocused)
            }
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityLabel(label)
        }
    }
}

public struct ConnectionFormPanel: View {
    public typealias ConnectAction = @MainActor (
        SourceConnectionRequest
    ) async -> SourceConnectionOutcome

    private enum Phase: Equatable {
        case idle
        case connecting
        case failed(String)
        case timedOut(String)
        case connected
    }

    private let kind: SourceConnectionKind
    private let identifierPrefix: String
    private let onConnect: ConnectAction
    private let onCancel: () -> Void
    private let onConnected: () -> Void

    @Binding private var name: String
    @Binding private var address: String
    @Binding private var share: String
    @Binding private var username: String
    @Binding private var password: String
    @Binding private var connectsAsGuest: Bool

    @State private var phase: Phase = .idle
    @State private var connectTask: Task<Void, Never>?

    public init(
        kind: SourceConnectionKind,
        name: Binding<String>,
        address: Binding<String>,
        share: Binding<String>,
        username: Binding<String>,
        password: Binding<String>,
        connectsAsGuest: Binding<Bool>,
        accessibilityIdentifierPrefix: String,
        onConnect: @escaping ConnectAction,
        onCancel: @escaping () -> Void = {},
        onConnected: @escaping () -> Void = {}
    ) {
        self.kind = kind
        _name = name
        _address = address
        _share = share
        _username = username
        _password = password
        _connectsAsGuest = connectsAsGuest
        identifierPrefix = accessibilityIdentifierPrefix
        self.onConnect = onConnect
        self.onCancel = onCancel
        self.onConnected = onConnected
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            header
            fields
            statusRegion
            actions
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: DesignTokens.SourceConnection.panelWidth, alignment: .leading)
        .clipShape(DesignTokens.ShapeToken.card)
        .enchronGlassBackground(in: DesignTokens.ShapeToken.card)
        .animation(DesignTokens.AnimationToken.selection, value: showsCredentials)
        .animation(DesignTokens.AnimationToken.selection, value: phase)
        .interactiveDismissDisabled(isBusy)
        .onDisappear { connectTask?.cancel() }
    }

    private var showsCredentials: Bool {
        kind == .webDAV || !connectsAsGuest
    }

    private var isBusy: Bool {
        phase == .connecting || phase == .connected
    }

    private var inputsComplete: Bool {
        guard !trimmed(address).isEmpty else { return false }
        if kind == .smb && trimmed(share).isEmpty {
            return false
        }
        return !showsCredentials || (!trimmed(username).isEmpty && !password.isEmpty)
    }

    private var connectDisabled: Bool {
        isBusy || !inputsComplete
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: kind.systemImage)
                .font(DesignTokens.SymbolSize.selectionHeaderIcon)
                .foregroundStyle(DesignTokens.Theme.accent)
                .frame(width: DesignTokens.Interactive.regular)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Connect to \(kind.title)")
                    .font(DesignTokens.Typography.headline)
                Text(kind.subtitle)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.supportingText)
            }
            Spacer(minLength: 0)
        }
    }

    private var credentialsTransition: AnyTransition {
        .asymmetric(
            insertion: AnyTransition.scale(scale: 0.96, anchor: .top)
                .combined(with: .opacity)
                .combined(with: .move(edge: .top))
                .animation(
                    DesignTokens.AnimationToken.selection.delay(
                        DesignTokens.SourceConnection.credentialRevealDelay
                    )
                ),
            removal: AnyTransition.opacity
                .animation(DesignTokens.AnimationToken.selection)
        )
    }

    @ViewBuilder
    private var fields: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            ConnectionFormField(
                label: "Display Name",
                placeholder: "Optional",
                text: $name,
                accessibilityIdentifier: identifier("name")
            )
            ConnectionFormField(
                label: kind.addressLabel,
                placeholder: kind.addressPlaceholder,
                text: $address,
                accessibilityIdentifier: identifier("address")
            )

            if kind == .smb {
                ConnectionFormField(
                    label: "Share",
                    placeholder: "Share name",
                    text: $share,
                    accessibilityIdentifier: identifier("share")
                )
            }

            if showsCredentials {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    ConnectionFormField(
                        label: "Username",
                        placeholder: "Username",
                        text: $username,
                        accessibilityIdentifier: identifier("username")
                    )
                    ConnectionFormField(
                        label: "Password",
                        placeholder: "Password",
                        text: $password,
                        isSecure: true,
                        accessibilityIdentifier: identifier("password")
                    )
                }
                .transition(credentialsTransition)
            }

            if kind == .smb {
                Toggle("Connect as Guest", isOn: $connectsAsGuest)
                    .font(DesignTokens.Typography.selectionHeader)
                    .tint(DesignTokens.Theme.accent)
                    .accessibilityIdentifier(identifier("guest"))
            }
        }
        .disabled(isBusy)
    }

    @ViewBuilder
    private var statusRegion: some View {
        Group {
            switch phase {
            case .idle:
                EmptyView()
            case .connecting:
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting…")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                }
            case .failed(let message):
                statusLine(
                    systemImage: "exclamationmark.triangle.fill",
                    text: message,
                    tint: DesignTokens.SourceConnection.failureColor,
                    identifier: identifier("error")
                )
            case .timedOut(let message):
                statusLine(
                    systemImage: "clock.badge.exclamationmark",
                    text: message,
                    tint: DesignTokens.SourceConnection.timeoutColor,
                    identifier: identifier("error")
                )
            case .connected:
                statusLine(
                    systemImage: "checkmark.circle.fill",
                    text: "Connected",
                    tint: DesignTokens.SourceConnection.successColor,
                    identifier: identifier("success")
                )
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func statusLine(
        systemImage: String,
        text: String,
        tint: Color,
        identifier: String
    ) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(text)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.Surface.accessoryText)
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier(identifier)
    }

    private var actions: some View {
        HStack(spacing: DesignTokens.Interactive.buttonSpacing) {
            Spacer(minLength: 0)
            GlassCapsuleIconLabelButton(
                title: "Cancel",
                systemName: "xmark",
                accessibilityLabel: "Cancel",
                action: cancel,
                accessibilityIdentifier: identifier("cancel")
            )
            GlassCapsuleIconLabelButton(
                title: "Connect",
                systemName: "link",
                accessibilityLabel: "Connect",
                action: connect,
                accessibilityIdentifier: identifier("connect")
            )
            .opacity(connectDisabled ? DesignTokens.SourceConnection.disabledActionOpacity : 1)
            .disabled(connectDisabled)
        }
    }

    private func connect() {
        connectTask?.cancel()
        phase = .connecting
        let request = SourceConnectionRequest(
            kind: kind,
            name: trimmed(name),
            address: trimmed(address),
            share: trimmed(share),
            username: trimmed(username),
            password: password,
            connectsAsGuest: kind == .smb && connectsAsGuest
        )

        connectTask = Task { @MainActor in
            let outcome = await onConnect(request)
            guard !Task.isCancelled else { return }

            switch outcome {
            case .connected:
                phase = .connected
                try? await Task.sleep(for: DesignTokens.SourceConnection.successHoldDuration)
                guard !Task.isCancelled else { return }
                onConnected()
            case .failed(let message):
                phase = .failed(message)
            case .timedOut(let message):
                phase = .timedOut(message)
            }
        }
    }

    private func cancel() {
        connectTask?.cancel()
        onCancel()
    }

    private func identifier(_ suffix: String) -> String {
        "\(identifierPrefix)-\(suffix)"
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
