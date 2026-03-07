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

    private var isValid: Bool { !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var navigationTitle: String {
        sourceType == .smb ? "Add SMB Server" : "Add WebDAV Server"
    }

    private var addressPrompt: String {
        sourceType == .smb ? "smb://192.168.1.20/share" : "http://192.168.1.10:5244/dav"
    }

    public init(sourceType: FileBrowsingDomain.SourceType) {
        self.sourceType = sourceType
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Server Address", text: $serverAddress, prompt: Text(addressPrompt))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)

                    TextField("Username (optional)", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)

                    SecureField("Password (optional)", text: $password)
                        .textContentType(.password)

                    TextField("Server Name (optional)", text: $displayName)
                }
                
                if let error = validationError {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
                
                Section {
                    Button(action: connectAndSave) {
                        if isConnecting {
                            HStack { ProgressView().padding(.trailing, 4); Text("Connecting...") }
                        } else {
                            Text("Connect")
                        }
                    }
                    .disabled(!isValid || isConnecting)
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func connectAndSave() {
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
