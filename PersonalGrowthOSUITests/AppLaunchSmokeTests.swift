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

        app.staticTexts["A restart-safe memory"].tap()
        app.buttons["entry-edit"].tap()
        let editor = app.textViews["entry-edit-body"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        app.typeKey("a", modifierFlags: .command)
        editor.typeText("An edited memory")
        app.buttons["entry-edit-save"].tap()
        XCTAssertTrue(app.staticTexts["An edited memory"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["-PGOSUITesting"]
        app.launch()
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["An edited memory"].waitForExistence(timeout: 5))
    }

    func testPermanentDeleteRemovesEntryFromTimeline() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData"]
        app.launch()

        app.buttons["quick-capture-button"].tap()
        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("Delete this memory")
        app.buttons["capture-save"].tap()
        app.staticTexts["Delete this memory"].tap()
        app.buttons["entry-actions"].tap()
        app.buttons["Delete Permanently"].tap()
        app.alerts.buttons["Delete"].tap()

        XCTAssertTrue(app.staticTexts["No Entries Yet"].waitForExistence(timeout: 5))
    }

    func testGlobalCaptureIsAvailableFromTimeline() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData"]
        app.launch()

        app.tabBars.buttons["Timeline"].tap()
        app.buttons["global-capture-button"].tap()

        XCTAssertTrue(app.textViews["capture-body"].waitForExistence(timeout: 5))
    }

    func testGlobalCaptureIsAvailableFromSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData"]
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["settings-capture-button"].tap()

        XCTAssertTrue(app.textViews["capture-body"].waitForExistence(timeout: 5))
    }

    func testArchivedEntryCanBeRestored() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData"]
        app.launch()

        app.buttons["quick-capture-button"].tap()
        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("Archive and restore me")
        app.buttons["capture-save"].tap()
        app.staticTexts["Archive and restore me"].tap()
        app.buttons["entry-actions"].tap()
        app.buttons["Archive"].tap()

        XCTAssertTrue(app.staticTexts["No Entries Yet"].waitForExistence(timeout: 5))
        app.buttons["Show Archived"].tap()
        XCTAssertTrue(app.staticTexts["Archive and restore me"].waitForExistence(timeout: 5))
        app.staticTexts["Archive and restore me"].tap()
        app.buttons["entry-actions"].tap()
        app.buttons["Restore"].tap()
        app.buttons["Show Active"].tap()

        XCTAssertTrue(app.staticTexts["Archive and restore me"].waitForExistence(timeout: 5))
    }
}
