import Foundation
import XCTest

/// Drives three ocean preview open/close cycles so the worldTiming probe rows
/// in the app journal capture the optimized startup path on device.
nonisolated final class OceanStartupTimingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
#if targetEnvironment(simulator)
        throw XCTSkip("Ocean startup timing requires Apple Vision Pro.")
#endif
    }

    @MainActor
    func testOceanPreviewThreeOpens() throws {
        let app = launchVisionProRegressionApp()

        let environmentTab = app.descendants(matching: .any)[
            "Navigation-Ornament-tab-environment"
        ].firstMatch
        guard requireHittable(environmentTab, named: "Environments", timeout: 30) else { return }
        environmentTab.tap()

        let volume = app.descendants(matching: .any)["SenseZone-VolumeRoot"].firstMatch
        guard requireHittable(volume, named: "Environment Card Volume", timeout: 20) else { return }

        for cycle in 1...3 {
            guard let open = firstHittableElement(
                matching: "EnvironmentCard-button-environment-ocean",
                in: app.buttons,
                timeout: 10
            ) else {
                XCTFail("Cycle \(cycle): ocean card toggle was not hittable for open.")
                return
            }
            open.tap()
            guard waitForState(
                in: app,
                identifier: "PlayerUI-application-state",
                timeout: 30,
                where: {
                    $0.string("environment") == "ocean"
                        && $0.string("immersiveSpaceResidency") == "open"
                }
            ) != nil else { return }
            Thread.sleep(forTimeInterval: 6)

            guard let close = firstHittableElement(
                matching: "EnvironmentCard-button-environment-ocean",
                in: app.buttons,
                timeout: 10
            ) else {
                XCTFail("Cycle \(cycle): ocean card toggle was not hittable for close.")
                return
            }
            close.tap()
            guard waitForState(
                in: app,
                identifier: "PlayerUI-application-state",
                timeout: 30,
                where: { $0.string("immersiveSpaceResidency") == "closed" }
            ) != nil else { return }
            Thread.sleep(forTimeInterval: 3)
        }
    }
}
