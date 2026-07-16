import XCTest

final class PersonalGrowthOSUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()

        app.launch()

        XCTAssertEqual(app.state, .runningForeground)
    }
}
