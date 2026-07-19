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

    func testFlagAppearsAsTodayContextAndIsSearchable() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData"]
        app.launch()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-goals"].tap()
        let title = app.textFields["new-goal-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Thirty Day Focus")
        app.segmentedControls.buttons["Flag"].tap()
        app.buttons["add-goal"].tap()
        app.keyboards.buttons["return"].tap()

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Thirty Day Focus"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Complete Thirty Day Focus"].exists)

        app.buttons["global-search-button"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("thirty day")
        XCTAssertTrue(app.buttons["search-goal-thirty day focus"].waitForExistence(timeout: 5))
        app.buttons["search-goal-thirty day focus"].tap()
        XCTAssertTrue(app.navigationBars["Thirty Day Focus"].waitForExistence(timeout: 5))
    }

    func testHabitSupportsGoalAndLifecycleAppearsInTimeline() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData"]
        app.launch()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()
        let habitName = app.textFields["new-habit-name"]
        XCTAssertTrue(habitName.waitForExistence(timeout: 5))
        habitName.tap()
        habitName.typeText("Read")
        app.buttons["add-habit"].tap()
        app.keyboards.buttons["return"].tap()
        app.navigationBars.buttons["Growth"].tap()

        app.buttons["growth-goals"].tap()
        let goalTitle = app.textFields["new-goal-title"]
        XCTAssertTrue(goalTitle.waitForExistence(timeout: 5))
        goalTitle.tap()
        goalTitle.typeText("Learn Swift")
        app.buttons["add-goal"].tap()
        app.keyboards.buttons["return"].tap()
        app.buttons["goal-learn swift"].tap()
        app.buttons["goal-manage-habits"].tap()
        app.buttons["Read"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Read supports this Goal"].waitForExistence(timeout: 5))

        app.buttons["goal-actions"].tap()
        app.buttons["Pause"].tap()
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["Goal Changes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Learn Swift"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 5))
    }

    func testManualReviewWithPeriodAppearsInTimelineLibraryAndSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData"]
        app.launch()

        app.tabBars.buttons["Library"].tap()
        app.buttons["library-new-review"].tap()
        XCTAssertTrue(app.switches["review-include-period"].waitForExistence(timeout: 5))
        app.switches["review-include-period"].tap()
        app.buttons["review-write"].tap()
        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("Weekly review reflection")
        app.buttons["capture-save"].tap()

        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["Weekly review reflection"].waitForExistence(timeout: 5))
        app.staticTexts["Weekly review reflection"].tap()
        XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review Period"].exists)

        app.tabBars.buttons["Library"].tap()
        app.buttons["library-all-entries"].tap()
        XCTAssertTrue(app.staticTexts["Weekly review reflection"].waitForExistence(timeout: 5))

        app.buttons["global-search-button"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("weekly review")
        XCTAssertTrue(app.staticTexts["Weekly review reflection"].waitForExistence(timeout: 5))
    }

    func testManualReviewCanRelateHabitAndGoal() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData"]
        app.launch()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()
        let habitName = app.textFields["new-habit-name"]
        XCTAssertTrue(habitName.waitForExistence(timeout: 5))
        habitName.tap()
        habitName.typeText("Meditate")
        app.buttons["add-habit"].tap()
        app.keyboards.buttons["return"].tap()
        app.navigationBars.buttons["Growth"].tap()
        app.buttons["growth-goals"].tap()
        let goalTitle = app.textFields["new-goal-title"]
        XCTAssertTrue(goalTitle.waitForExistence(timeout: 5))
        goalTitle.tap()
        goalTitle.typeText("Stay Present")
        app.buttons["add-goal"].tap()
        app.keyboards.buttons["return"].tap()

        app.tabBars.buttons["Library"].tap()
        app.buttons["library-new-review"].tap()
        XCTAssertTrue(app.buttons["review-habit-meditate"].waitForExistence(timeout: 5))
        app.buttons["review-habit-meditate"].tap()
        app.buttons["review-goal-stay present"].tap()
        app.buttons["review-write"].tap()
        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("Habit and Goal review")
        app.buttons["capture-save"].tap()

        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["Habit and Goal review"].waitForExistence(timeout: 5))
        app.staticTexts["Habit and Goal review"].tap()
        XCTAssertTrue(app.staticTexts["Meditate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Stay Present"].waitForExistence(timeout: 5))
        app.buttons["entry-manage-relationships"].tap()
        XCTAssertTrue(app.navigationBars["Reviewed Objects"].waitForExistence(timeout: 5))
    }
}
