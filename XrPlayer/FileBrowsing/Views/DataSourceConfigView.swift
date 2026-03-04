import SwiftUI

public struct DataSourceConfigView: View {
    public init() {}
    
    public var body: some View {
        Form {
            Section("SMB") {
                TextField("Server Address", text: .constant(""))
                TextField("User", text: .constant(""))
                SecureField("Password", text: .constant(""))
            }
            
            Section {
                Button("Connect") {}
            }
        }
        .navigationTitle("Add Source")
    }
}
