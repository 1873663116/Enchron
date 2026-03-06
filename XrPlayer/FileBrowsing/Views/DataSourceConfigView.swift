import SwiftUI

public struct DataSourceConfigView: View {
    @Environment(FileBrowsingViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedType: FileBrowsingDomain.SourceType = .webDAV
    @State private var displayName = ""
    @State private var host = ""
    @State private var portText = ""
    @State private var rootPath = "/"
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var validationError: String?
    
    private var defaultPort: Int { selectedType == .smb ? 445 : 443 }
    private var isValid: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty && !displayName.trimmingCharacters(in: .whitespaces).isEmpty }
    private var rootPathLabel: String { selectedType == .smb ? "Share Path" : "Root Path" }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Protocol") {
                    Picker("Type", selection: $selectedType) {
                        Text("WebDAV").tag(FileBrowsingDomain.SourceType.webDAV)
                        Text("SMB").tag(FileBrowsingDomain.SourceType.smb)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedType) { _, new in
                        portText = "" // reset port on type change
                    }
                }
                
                Section("Server") {
                    TextField("Display Name", text: $displayName)
                    TextField("Server Address (host or IP)", text: $host)
                        .textContentType(.URL)
                    HStack {
                        TextField("Port (default: \(defaultPort))", text: $portText)
                            .keyboardType(.numberPad)
                    }
                    TextField(rootPathLabel, text: $rootPath)
                }
                
                Section("Authentication") {
                    TextField("Username (optional)", text: $username)
                        .textContentType(.username)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
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
                            Text("Connect & Save")
                        }
                    }
                    .disabled(!isValid || isConnecting)
                }
            }
            .navigationTitle("Add Remote Source")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func connectAndSave() {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, !trimmedName.isEmpty else {
            validationError = "Display name and server address are required."
            return
        }
        guard trimmedUsername.isEmpty == false || password.isEmpty else {
            validationError = "Username is required when a password is provided."
            return
        }
        let port = Int(portText) ?? defaultPort
        let info = FileBrowsingDomain.ConnectionInfo(
            sourceType: selectedType,
            host: trimmedHost,
            port: port,
            username: trimmedUsername.isEmpty ? nil : trimmedUsername,
            rootPath: rootPath.isEmpty ? "/" : rootPath
        )
        let ds = FileBrowsingDomain.DataSource(name: trimmedName, sourceType: selectedType, connectionInfo: info)

        isConnecting = true
        validationError = nil
        Task {
            let didConnect = await viewModel.connectAndSaveRemoteDataSource(ds, password: password)
            isConnecting = false
            if didConnect {
                dismiss()
            } else {
                validationError = viewModel.lastErrorMessage
                viewModel.lastErrorMessage = nil
            }
        }
    }
}
