import XCTest

final class AppLaunchSmokeTests: XCTestCase {
    func testUITestingLaunchShowsPlaceholder() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting"]

        app.launch()

        let placeholder = app.descendants(matching: .any)["root-placeholder"]
        XCTAssertTrue(placeholder.waitForExistence(timeout: 5))
    }
}
