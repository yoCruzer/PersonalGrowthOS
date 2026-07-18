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

    func testLibraryOrganizesEntryWithoutRequiringTag() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData"]
        app.launch()

        app.buttons["quick-capture-button"].tap()
        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("Organize without tags")
        app.buttons["capture-save"].tap()
        app.staticTexts["Organize without tags"].tap()
        app.buttons["entry-actions"].tap()
        app.buttons["Mark Organized"].tap()

        app.tabBars.buttons["Library"].tap()
        app.buttons["library-inbox"].tap()
        XCTAssertTrue(app.staticTexts["No Inbox"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Library"].tap()
        app.buttons["library-all-entries"].tap()
        XCTAssertTrue(app.staticTexts["Organize without tags"].waitForExistence(timeout: 5))
    }

    func testTagLinkAndGlobalSearchFindEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData"]
        app.launch()

        app.buttons["quick-capture-button"].tap()
        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("Searchable reflection")
        app.buttons["capture-save"].tap()

        app.tabBars.buttons["Library"].tap()
        app.buttons["library-tags"].tap()
        let tagName = app.textFields["new-tag-name"]
        XCTAssertTrue(tagName.waitForExistence(timeout: 5))
        tagName.tap()
        tagName.typeText("Learning")
        app.buttons["add-tag"].tap()
        app.keyboards.buttons["return"].tap()

        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["timeline-view"].waitForExistence(timeout: 5))
        app.staticTexts["Searchable reflection"].tap()
        app.buttons["entry-manage-tags"].tap()
        XCTAssertTrue(app.buttons["Learning"].waitForExistence(timeout: 5))
        app.buttons["Learning"].tap()
        app.buttons["Done"].tap()
        app.buttons["global-search-button"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("learning")
        XCTAssertTrue(app.staticTexts["Learning"].waitForExistence(timeout: 5))
        app.buttons["Learning"].tap()
        XCTAssertTrue(app.staticTexts["Searchable reflection"].waitForExistence(timeout: 5))
    }

    func testTodayHabitCheckInAppearsInHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData"]
        app.launch()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()
        let name = app.textFields["new-habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Read")
        app.buttons["add-habit"].tap()
        app.keyboards.buttons["return"].tap()

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["Check in Read"].waitForExistence(timeout: 5))
        app.buttons["Check in Read"].tap()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["habit-read"].tap()
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5))
    }

    func testHabitInsightCreatesLinkedEntryAndHabitIsSearchable() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData"]
        app.launch()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()
        let name = app.textFields["new-habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Reflect")
        app.buttons["add-habit"].tap()
        app.keyboards.buttons["return"].tap()
        app.buttons["habit-reflect"].tap()
        app.buttons["habit-check-in-insight"].tap()

        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("Habit insight entry")
        app.buttons["capture-save"].tap()
        XCTAssertTrue(app.staticTexts["Linked Entry"].waitForExistence(timeout: 5))

        app.buttons["global-search-button"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("reflect")
        XCTAssertTrue(app.buttons["search-habit-reflect"].waitForExistence(timeout: 5))
        app.buttons["search-habit-reflect"].tap()
        XCTAssertTrue(app.navigationBars["Reflect"].waitForExistence(timeout: 5))
    }
}
