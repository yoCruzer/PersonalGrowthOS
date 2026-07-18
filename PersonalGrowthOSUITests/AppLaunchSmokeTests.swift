import XCTest

final class AppLaunchSmokeTests: XCTestCase {
    func testUITestingLaunchShowsAppShell() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting"]

        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["app-shell"].waitForExistence(timeout: 5))
    }

    func testTextCaptureAppearsInTimelineAndSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData"]
        app.launch()

        app.buttons["quick-capture-button"].tap()
        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("A restart-safe memory")
        app.buttons["capture-save"].tap()

        XCTAssertTrue(app.staticTexts["A restart-safe memory"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["-PGOSUITesting"]
        app.launch()
        app.tabBars.buttons["Timeline"].tap()

        XCTAssertTrue(app.staticTexts["A restart-safe memory"].waitForExistence(timeout: 5))
    }
}
