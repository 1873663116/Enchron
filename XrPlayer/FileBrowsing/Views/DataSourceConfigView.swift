import SwiftUI

public struct DataSourceConfigView: View {
    @Environment(FileBrowsingViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    private let sourceType: FileBrowsingDomain.SourceType
    @State private var displayName = ""
    @State private var serverAddress = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var validationError: String?

    // SMB two-stage flow
    @State private var smbShares: [String] = []
    @State private var showSharePicker = false
    @State private var smbAdapter: SMBDataSourceAdapter?

    private var isSMB: Bool { sourceType == .smb }

    private var isValid: Bool { !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var navigationTitle: String {
        isSMB ? "Add SMB Server" : "Add WebDAV Server"
    }

    private var addressPrompt: String {
        isSMB ? "192.168.1.20" : "http://192.168.1.10:5244/dav"
    }

    private var addressLabel: String {
        isSMB ? "Server IP Address" : "Server Address"
    }

    public init(sourceType: FileBrowsingDomain.SourceType) {
        self.sourceType = sourceType
    }

    public var body: some View {
        NavigationStack {
            if showSharePicker {
                sharePickerView
            } else {
                connectionFormView
            }
        }
    }

    // MARK: - Connection Form

    @ViewBuilder
    private var connectionFormView: some View {
        Form {
            Section("Connection") {
                TextField(addressLabel, text: $serverAddress, prompt: Text(addressPrompt))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(isSMB ? nil : .URL)
                    .keyboardType(isSMB ? .decimalPad : .URL)
                    .accessibilityIdentifier("FileBrowsing-DataSourceConfig-textField-serverAddress")
                    .onChange(of: serverAddress) { _, newValue in
                        if isSMB {
                            // Only allow digits and dots for SMB IP input
                            let filtered = newValue.filter { $0.isNumber || $0 == "." }
                            if filtered != newValue {
                                serverAddress = filtered
                            }
                        }
                    }

                TextField("Username (optional)", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .accessibilityIdentifier("FileBrowsing-DataSourceConfig-textField-username")

                SecureField("Password (optional)", text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("FileBrowsing-DataSourceConfig-secureField-password")

                TextField("Server Name (optional)", text: $displayName)
                    .accessibilityIdentifier("FileBrowsing-DataSourceConfig-textField-displayName")
            }

            if isSMB {
                Section {
                    Text("Enter the server IP address only. You will select a shared folder after connecting.")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = validationError {
                Section {
                    Text(error)
                        .foregroundStyle(.orange)
                        .font(DesignTokens.Typography.metadata)
                }
            }

            Section {
                Button(action: connectAction) {
                    if isConnecting {
                        HStack { ProgressView().padding(.trailing, 4); Text("Connecting...") }
                    } else {
                        Text("Connect")
                    }
                }
                .frame(minHeight: 60)
                .contentShape(.rect)
                .disabled(!isValid || isConnecting)
                .accessibilityIdentifier("FileBrowsing-DataSourceConfig-button-connect")
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("FileBrowsing-DataSourceConfig-button-cancel")
            }
        }
    }

    // MARK: - Share Picker (SMB only)

    @ViewBuilder
    private var sharePickerView: some View {
        List {
            if smbShares.isEmpty {
                Text("No shares found on this server.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(smbShares, id: \.self) { shareName in
                    Button {
                        selectSMBShare(shareName)
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.enchronTertiary)
                            Text(shareName)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(DesignTokens.Typography.metadata)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 60)
                        .contentShape(.rect)
                    }
                    .accessibilityIdentifier("FileBrowsing-DataSourceConfig-button-share-\(shareName)")
                    .accessibilityLabel("\(shareName), shared folder")
                    .accessibilityHint("Connects to this SMB share")
                }
            }
        }
        .navigationTitle("Select Share")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") {
                    showSharePicker = false
                    smbAdapter?.disconnect()
                    smbAdapter = nil
                }
                .accessibilityIdentifier("FileBrowsing-DataSourceConfig-button-backFromSharePicker")
            }
        }
    }

    // MARK: - Actions

    private func connectAction() {
        if isSMB {
            connectSMBTwoStage()
        } else {
            connectAndSaveWebDAV()
        }
    }

    private func connectSMBTwoStage() {
        let trimmedAddress = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAddress.isEmpty == false else {
            validationError = "Server address is required."
            return
        }

        let info: FileBrowsingDomain.ConnectionInfo
        do {
            info = try .remote(
                sourceType: .smb,
                address: trimmedAddress,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : username.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            validationError = error.localizedDescription
            return
        }

        isConnecting = true
        validationError = nil

        let adapter = SMBDataSourceAdapter(credentialStore: viewModel.credentialStoreForConfig)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let ds = FileBrowsingDomain.DataSource(
            name: displayName.trimmingCharacters(in: .whitespaces).isEmpty
                ? (info.host ?? trimmedAddress)
                : displayName.trimmingCharacters(in: .whitespaces),
            sourceType: .smb,
            connectionInfo: info
        )

        Task {
            if trimmedUsername.isEmpty == false || password.isEmpty == false {
                viewModel.saveCredential(for: ds, username: trimmedUsername, password: password)
            }

            do {
                try await adapter.connect(with: info)

                let shares = try await adapter.listShares()
                smbShares = shares
                smbAdapter = adapter
                showSharePicker = true
            } catch {
                validationError = error.localizedDescription
            }

            isConnecting = false
        }
    }

    private func selectSMBShare(_ shareName: String) {
        guard let adapter = smbAdapter, let info = adapter.currentConnectionInfo else { return }

        isConnecting = true
        Task {
            do {
                try await adapter.selectShare(shareName)

                let updatedInfo = info.withSMBShare(shareName)
                let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
                let finalName = trimmedName.isEmpty ? "\(info.host ?? serverAddress)/\(shareName)" : trimmedName
                let ds = FileBrowsingDomain.DataSource(
                    name: finalName,
                    sourceType: .smb,
                    connectionInfo: updatedInfo
                )

                await viewModel.connectToDataSource(ds)
                if viewModel.lastErrorMessage == nil {
                    viewModel.addDataSource(ds)
                    dismiss()
                } else {
                    validationError = viewModel.lastErrorMessage
                    viewModel.lastErrorMessage = nil
                }
            } catch {
                validationError = error.localizedDescription
            }
            isConnecting = false
        }
    }

    private func connectAndSaveWebDAV() {
        let trimmedAddress = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAddress.isEmpty == false else {
            validationError = "Server address is required."
            return
        }

        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        let info: FileBrowsingDomain.ConnectionInfo
        do {
            info = try .remote(
                sourceType: sourceType,
                address: trimmedAddress,
                username: trimmedUsername.isEmpty ? nil : trimmedUsername
            )
        } catch {
            validationError = error.localizedDescription
            return
        }

        let finalName = trimmedName.isEmpty ? (info.host ?? trimmedAddress) : trimmedName
        let ds = FileBrowsingDomain.DataSource(name: finalName, sourceType: sourceType, connectionInfo: info)

        isConnecting = true
        validationError = nil
        Task {
            if trimmedUsername.isEmpty == false || password.isEmpty == false {
                viewModel.saveCredential(for: ds, username: trimmedUsername, password: password)
            }

            await viewModel.connectToDataSource(ds)
            isConnecting = false

            if viewModel.lastErrorMessage == nil {
                viewModel.addDataSource(ds)
                dismiss()
            } else {
                validationError = viewModel.lastErrorMessage
                viewModel.lastErrorMessage = nil
            }
        }
    }
}
