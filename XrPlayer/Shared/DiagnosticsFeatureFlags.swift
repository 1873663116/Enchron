import Foundation

enum DiagnosticsFeatureFlags {
    static let hdrLabEnabled: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()
}
