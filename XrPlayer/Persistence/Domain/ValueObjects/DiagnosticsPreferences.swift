import Foundation

nonisolated extension PersistenceDomain {
    /// Diagnostic log verbosity (SET-23).
    public enum LogLevel: String, Sendable, Equatable, CaseIterable, Codable {
        case off
        case error
        case info
        case verbose
    }

    /// When verbose logging automatically reverts to a quieter level (advanced logs).
    public enum VerboseAutoOff: String, Sendable, Equatable, CaseIterable, Codable {
        case nextLaunch
        case thirtyMinutes
    }
}
