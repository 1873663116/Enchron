import DesignSystem
import Foundation
import SwiftUI

public typealias SourceConnectionKind = FileBrowsingDomain.SourceType

public struct SourceConnectionRequest: Sendable, Equatable {
    public let kind: SourceConnectionKind
    public let name: String
    public let address: String
    public let username: String
    public let password: String
    public let connectsAsGuest: Bool

    public init(
        kind: SourceConnectionKind,
        name: String,
        address: String,
        username: String,
        password: String,
        connectsAsGuest: Bool
    ) {
        self.kind = kind
        self.name = name
        self.address = address
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
    @Binding private var username: String
    @Binding private var password: String
    @Binding private var connectsAsGuest: Bool

    @State private var phase: Phase = .idle
    @State private var connectTask: Task<Void, Never>?

    public init(
        kind: SourceConnectionKind,
        name: Binding<String>,
        address: Binding<String>,
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
        kind.alwaysShowsCredentials || !connectsAsGuest
    }

    private var isBusy: Bool {
        phase == .connecting || phase == .connected
    }

    private var inputsComplete: Bool {
        guard !trimmed(address).isEmpty else { return false }
        return !showsCredentials || (!trimmed(username).isEmpty && !password.isEmpty)
    }

    private var connectDisabled: Bool {
        isBusy || !inputsComplete
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: kind.connectionIcon)
                .font(DesignTokens.SymbolSize.selectionHeaderIcon)
                .foregroundStyle(DesignTokens.Theme.accent)
                .frame(width: DesignTokens.Interactive.regular)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Connect to \(kind.title)")
                    .font(DesignTokens.Typography.headline)
                Text(kind.connectionSubtitle)
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
            labelledField("Display Name", identifierSuffix: "name") {
                TextField("Display Name", text: $name, prompt: Text("Optional"))
            }
            labelledField(kind.addressLabel, identifierSuffix: "address") {
                TextField(
                    kind.addressLabel,
                    text: $address,
                    prompt: Text(kind.addressPlaceholder)
                )
            }

            if showsCredentials {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    labelledField("Username", identifierSuffix: "username") {
                        TextField(
                            "Username",
                            text: $username,
                            prompt: Text("Username")
                        )
                    }
                    labelledField("Password", identifierSuffix: "password") {
                        SecureField(
                            "Password",
                            text: $password,
                            prompt: Text("Password")
                        )
                    }
                }
                .transition(credentialsTransition)
            }

            if kind.allowsGuestAccess {
                Toggle("Connect as Guest", isOn: $connectsAsGuest)
                    .font(DesignTokens.Typography.selectionHeader)
                    .tint(DesignTokens.Theme.accent)
                    .accessibilityIdentifier(identifier("guest"))
            }
        }
        .textFieldStyle(.roundedBorder)
        .enchronLiteralTextInput()
        .disabled(isBusy)
    }

    private func labelledField(
        _ label: String,
        identifierSuffix: String,
        @ViewBuilder field: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(label)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Surface.supportingText)
            field()
                .accessibilityIdentifier(identifier(identifierSuffix))
                .accessibilityLabel(label)
        }
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
