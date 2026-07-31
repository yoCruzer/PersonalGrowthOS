import XCTest

final class AppLaunchSmokeTests: XCTestCase {
    func testCoreShellPassesAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["app-shell"].waitForExistence(timeout: 5))
        try performSemanticAccessibilityAudit(app)
        for tab in ["Timeline", "Growth", "Library"] {
            app.tabBars.buttons[tab].tap()
            try performSemanticAccessibilityAudit(app)
        }
        app.tabBars.buttons["Today"].tap()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        try performSemanticAccessibilityAudit(app)
    }

    func testCoreShellRemainsOperableAtLargestAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PGOSUITesting", "-PGOSResetData",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["quick-capture-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quick-capture-button"].isHittable)
        app.tabBars.buttons["Growth"].tap()
        XCTAssertTrue(app.buttons["growth-goals"].isHittable)
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["library-all-entries"].isHittable)
        app.tabBars.buttons["Today"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings-import-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-import-button"].isHittable)
    }

    func testUITestingLaunchShowsAppShell() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["app-shell"].waitForExistence(timeout: 5))
    }

    func testTextCaptureAppearsInTimelineAndSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.buttons["quick-capture-button"].tap()
        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("A restart-safe memory")
        app.buttons["capture-save"].tap()

        XCTAssertTrue(app.staticTexts["A restart-safe memory"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["-PGOSUITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Timeline"].tap()

        XCTAssertTrue(app.staticTexts["A restart-safe memory"].waitForExistence(timeout: 5))

        app.staticTexts["A restart-safe memory"].tap()
        app.buttons["entry-edit"].tap()
        let editor = app.textViews["entry-edit-body"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(" edited")
        app.buttons["entry-edit-save"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["A restart-safe memory edited"].waitForExistence(timeout: 10))

        app.terminate()
        app.launchArguments = ["-PGOSUITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["app-shell"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["A restart-safe memory edited"].waitForExistence(timeout: 10))
    }

    func testPermanentDeleteRemovesEntryFromTimeline() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.tabBars.buttons["Timeline"].tap()
        app.buttons["global-capture-button"].tap()

        XCTAssertTrue(app.textViews["capture-body"].waitForExistence(timeout: 5))
    }

    func testGlobalCaptureIsAvailableFromSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["settings-capture-button"].tap()

        XCTAssertTrue(app.textViews["capture-body"].waitForExistence(timeout: 5))
    }

    func testSettingsExposeSafeManualBackupAndRestore() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings-export-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-import-button"].exists)
        app.buttons["settings-export-button"].tap()

        XCTAssertTrue(app.buttons["Export and Share"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The ZIP may contain private entry text and original photos. Handle it as sensitive data."].exists)
    }

    func testGlobalCaptureIsAvailableFromSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.buttons["global-search-button"].tap()
        XCTAssertTrue(app.buttons["search-capture-button"].waitForExistence(timeout: 5))
        app.buttons["search-capture-button"].tap()

        XCTAssertTrue(app.textViews["capture-body"].waitForExistence(timeout: 5))
    }

    func testArchivedEntryCanBeRestored() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
        XCTAssertEqual(app.buttons["Learning"].value as? String, "Selected")
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

    private func performSemanticAccessibilityAudit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .trait
        ])
    }

    func testTodayHabitCheckInAppearsInHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()
        app.buttons["add-habit"].tap()
        let name = app.textFields["habit-editor-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Read")
        app.buttons["habit-editor-save"].tap()

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["Check in Read"].waitForExistence(timeout: 5))
        app.buttons["Check in Read"].tap()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["habit-read"].tap()
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5))
    }

    func testHabitInsightCreatesLinkedEntryAndHabitIsSearchable() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()
        app.buttons["add-habit"].tap()
        let name = app.textFields["habit-editor-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Reflect")
        app.buttons["habit-editor-save"].tap()
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
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()
        app.buttons["add-habit"].tap()
        let habitName = app.textFields["habit-editor-name"]
        XCTAssertTrue(habitName.waitForExistence(timeout: 5))
        habitName.tap()
        habitName.typeText("Read")
        app.buttons["habit-editor-save"].tap()
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
        XCTAssertTrue(app.staticTexts["Goal Change"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Learn Swift"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 5))
    }

    func testManualReviewWithPeriodAppearsInTimelineLibraryAndSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()
        app.buttons["add-habit"].tap()
        let habitName = app.textFields["habit-editor-name"]
        XCTAssertTrue(habitName.waitForExistence(timeout: 5))
        habitName.tap()
        habitName.typeText("Meditate")
        app.buttons["habit-editor-save"].tap()
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

    func testSystemLanguageSelectsSimplifiedChineseAndEnglishResources() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PGOSUITesting", "-PGOSResetData",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_Hans_CN"
        ]
        app.launch()

        for tab in ["今天", "时间线", "成长", "资料库"] {
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.buttons["quick-capture-button"].label.contains("快速记录"))
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = [
            "-PGOSUITesting", "-PGOSResetData",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        for tab in ["Today", "Timeline", "Growth", "Library"] {
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.buttons["quick-capture-button"].label.contains("Quick Capture"))
    }

    func testTodayAndTagEmptyStatesOfferClearStartingActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Record Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["today-open-growth"].isHittable)

        app.tabBars.buttons["Library"].tap()
        app.buttons["library-tags"].tap()
        XCTAssertTrue(app.staticTexts["Create Your First Tag"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["create-first-tag"].isHittable)
        app.buttons["create-first-tag"].tap()
        XCTAssertTrue(app.textFields["new-tag-name"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }

    func testGoalAndFlagOpenEditAndPersistAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-goals"].tap()
        let title = app.textFields["new-goal-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Device Goal")
        app.buttons["add-goal"].tap()
        title.tap()
        title.typeText("Device Flag")
        app.segmentedControls.buttons["Flag"].tap()
        app.buttons["add-goal"].tap()
        app.keyboards.buttons["return"].tap()

        app.tabBars.buttons["Today"].tap()
        app.buttons["today-goal-device goal"].tap()
        XCTAssertTrue(app.navigationBars["Device Goal"].waitForExistence(timeout: 5))
        app.buttons["goal-edit"].tap()
        let goalEditor = app.textFields["goal-editor-title"]
        XCTAssertTrue(goalEditor.waitForExistence(timeout: 5))
        goalEditor.tap()
        goalEditor.typeText(" Edited")
        app.buttons["goal-editor-save"].tap()
        XCTAssertTrue(goalEditor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Device Goal Edited"].waitForExistence(timeout: 10))

        app.navigationBars.buttons["Today"].tap()
        app.buttons["today-goal-device flag"].tap()
        XCTAssertTrue(app.navigationBars["Device Flag"].waitForExistence(timeout: 5))
        app.buttons["goal-edit"].tap()
        let flagEditor = app.textFields["goal-editor-title"]
        flagEditor.tap()
        flagEditor.typeText(" Edited")
        app.buttons["goal-editor-save"].tap()
        XCTAssertTrue(flagEditor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Device Flag Edited"].waitForExistence(timeout: 10))

        app.terminate()
        app.launchArguments = ["-PGOSUITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["app-shell"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["today-goal-device goal edited"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["today-goal-device flag edited"].waitForExistence(timeout: 10))
    }

    func testWeightEntryIsAccessiblePersistsAndShowsLatestValue() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["today-weight"].waitForExistence(timeout: 5))
        app.buttons["today-weight"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["weight-empty-state"].waitForExistence(timeout: 5))
        app.buttons["add-weight"].tap()
        let value = app.textFields["weight-editor-value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        value.tap()
        value.typeText("72.5")
        app.buttons["weight-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["weight-latest-value"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["weight-latest-value"].label, "72.5 kg")

        app.terminate()
        app.launchArguments = ["-PGOSUITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["today-latest-weight"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["today-latest-weight"].label, "72.5 kg")
    }
}
