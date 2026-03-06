import SwiftUI

public struct DataSourceConfigView: View {
    @Environment(FileBrowsingViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var displayName = ""
    @State private var selectedType: FileBrowsingDomain.SourceType = .webDAV
    @State private var portText = ""
    @State private var rootPath = "/"
    @State private var useCredentials = false
    @State private var username = ""
    @State private var password = ""
    @State private var showAdvancedOptions = false
    @State private var isConnecting = false
    @State private var validationError: String?

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedAddress: ParsedAddress? {
        ParsedAddress(rawValue: trimmedAddress)
    }

    private var effectiveType: FileBrowsingDomain.SourceType {
        parsedAddress?.sourceType ?? selectedType
    }

    private var defaultPort: Int {
        if let parsedDefault = parsedAddress?.defaultPort {
            return parsedDefault
        }
        return effectiveType == .smb ? 445 : 443
    }

    private var isValid: Bool {
        trimmedAddress.isEmpty == false
    }

    private var rootPathLabel: String {
        effectiveType == .smb ? "Share Path (optional)" : "Root Path (optional)"
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Server Address", text: $address)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    Text("Examples: `smb://192.168.1.10`, `https://nas.local/dav`, `nas.local`")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Name (optional, defaults to address)", text: $displayName)
                }

                Section("Authentication (Optional)") {
                    Toggle("Use Username and Password", isOn: $useCredentials.animation())
                    if useCredentials {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    }
                }

                DisclosureGroup("Advanced (Optional)", isExpanded: $showAdvancedOptions) {
                    Picker("Protocol", selection: $selectedType) {
                        Text("WebDAV").tag(FileBrowsingDomain.SourceType.webDAV)
                        Text("SMB").tag(FileBrowsingDomain.SourceType.smb)
                    }
                    .pickerStyle(.segmented)

                    if let scheme = parsedAddress?.scheme {
                        Text("Protocol is inferred from address scheme: `\(scheme)`")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Port (default: \(defaultPort))", text: $portText)
                        .keyboardType(.numberPad)
                    TextField(rootPathLabel, text: $rootPath)
                }

                if let error = validationError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
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
        guard trimmedAddress.isEmpty == false else {
            validationError = "Server address is required."
            return
        }

        let parsedAddress = parsedAddress
        let sourceType = parsedAddress?.sourceType ?? selectedType
        let resolvedHost = parsedAddress?.host ?? trimmedAddress
        guard resolvedHost.isEmpty == false else {
            validationError = "Please enter a valid server address."
            return
        }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let wantsCredential = useCredentials || trimmedUsername.isEmpty == false || trimmedPassword.isEmpty == false

        guard wantsCredential == false || trimmedUsername.isEmpty == false else {
            validationError = "Username is required when password is provided."
            return
        }

        let resolvedName: String
        if trimmedName.isEmpty {
            resolvedName = parsedAddress?.host ?? trimmedAddress
        } else {
            resolvedName = trimmedName
        }

        let parsedPath = parsedAddress?.path ?? "/"
        let normalizedRootPath = normalizePath(rootPath)
        let resolvedRootPath = parsedPath == "/" ? normalizedRootPath : normalizePath(parsedPath)
        let resolvedPort = parsedAddress?.port ?? Int(portText) ?? defaultPort

        let info = FileBrowsingDomain.ConnectionInfo(
            sourceType: sourceType,
            host: resolvedHost,
            port: resolvedPort,
            username: wantsCredential ? trimmedUsername : nil,
            rootPath: resolvedRootPath
        )
        let ds = FileBrowsingDomain.DataSource(name: resolvedName, sourceType: sourceType, connectionInfo: info)

        isConnecting = true
        validationError = nil
        Task {
            let didConnect = await viewModel.connectAndSaveRemoteDataSource(
                ds,
                password: wantsCredential ? password : ""
            )
            isConnecting = false
            if didConnect {
                dismiss()
            } else {
                let message = viewModel.lastErrorMessage
                if wantsCredential == false, shouldPromptForCredentialInput(message) {
                    useCredentials = true
                    validationError = "This server requires credentials. Enter username and password to continue."
                    viewModel.lastErrorMessage = nil
                    return
                }

                validationError = message
                viewModel.lastErrorMessage = nil
            }
        }
    }

    private func normalizePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "/" }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }

    private func shouldPromptForCredentialInput(_ message: String?) -> Bool {
        guard let message else { return false }
        let lowercased = message.lowercased()
        let authIndicators = [
            "401",
            "403",
            "unauthorized",
            "authentication",
            "forbidden",
            "access denied",
            "logon"
        ]
        return authIndicators.contains { lowercased.contains($0) }
    }
}

private struct ParsedAddress {
    let sourceType: FileBrowsingDomain.SourceType?
    let scheme: String?
    let host: String?
    let port: Int?
    let path: String
    let defaultPort: Int?

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if trimmed.contains("://"), let components = URLComponents(string: trimmed) {
            let normalizedScheme = components.scheme?.lowercased()
            self.scheme = normalizedScheme
            self.host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.port = components.port
            self.path = Self.normalizedPath(components.path)

            switch normalizedScheme {
            case "smb":
                self.sourceType = .smb
                self.defaultPort = 445
            case "http":
                self.sourceType = .webDAV
                self.defaultPort = 80
            case "https", "webdav", "dav":
                self.sourceType = .webDAV
                self.defaultPort = 443
            default:
                self.sourceType = nil
                self.defaultPort = nil
            }
            return
        }

        let components = URLComponents(string: "placeholder://\(trimmed)")
        self.scheme = nil
        self.sourceType = nil
        self.defaultPort = nil
        self.host = components?.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
        self.port = components?.port
        self.path = Self.normalizedPath(components?.path ?? "/")
    }

    private static func normalizedPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "/" }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }
}
