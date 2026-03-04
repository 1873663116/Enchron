import Foundation

extension PersistenceDomain {
    public struct UserPreferences: Sendable, Equatable {
        public var resumePolicy: ResumePolicy
        public var defaultEnvironmentID: String?

        public init(
            resumePolicy: ResumePolicy = .askEveryTime,
            defaultEnvironmentID: String? = nil
        ) {
            self.resumePolicy = resumePolicy
            self.defaultEnvironmentID = defaultEnvironmentID
        }
    }
}
