import Foundation

enum StreamDebugSwitches {
    static let disabled: Set<String> = {
#if DEBUG
        let raw = ProcessInfo.processInfo.environment["ENCHRON_STREAM_DISABLE"] ?? ""
        return Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
#else
        return []
#endif
    }()

    static func isDisabled(_ name: String) -> Bool {
        disabled.contains(name)
    }
}
