import Foundation

private final class EnchronDomainTestBundleToken: NSObject {}

extension Bundle {
    static let module = Bundle(for: EnchronDomainTestBundleToken.self)
}
