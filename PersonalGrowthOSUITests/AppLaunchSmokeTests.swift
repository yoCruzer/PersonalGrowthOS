import XCTest

final class AppLaunchSmokeTests: XCTestCase {
    func testCoreShellPassesAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["app-shell"].waitForExistence(timeout: 5))
        try performSemanticAccessibilityAudit(app)
        for tab in ["Timeline", "Record", "Growth", "Library"] {
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

    func testRecordTabIsTheNativeCaptureDestination() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Record"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["global-capture-button"].exists)
        app.tabBars.buttons["Record"].tap()

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
        XCTAssertTrue(app.staticTexts["The ZIP may contain private personal records, entry text, and original photos. Handle it as sensitive data."].exists)
    }

    func testSearchIsAvailableFromLibraryWithoutDuplicateCapture() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.tabBars.buttons["Library"].tap()
        app.buttons["library-search-button"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search-capture-button"].exists)
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
        app.navigationBars.buttons["Timeline"].tap()
        app.tabBars.buttons["Library"].tap()
        app.navigationBars.buttons["Library"].tap()
        app.buttons["library-search-button"].tap()
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
        let completedCheckIn = app.buttons["habit-check-in"]
        XCTAssertTrue(completedCheckIn.waitForExistence(timeout: 5))
        XCTAssertEqual(completedCheckIn.label, "Completed Today")
        XCTAssertFalse(completedCheckIn.isEnabled)
    }

    func testHabitOverviewSupportsDirectCheckIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()
        app.buttons["add-habit"].tap()
        let name = app.textFields["habit-editor-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Walk")
        app.buttons["habit-editor-save"].tap()

        let checkIn = app.buttons["habit-overview-check-in"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        checkIn.tap()
        XCTAssertFalse(checkIn.isEnabled)
    }

    func testRepeatableHabitCounterIncrementsDecrementsAndPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PGOSUITesting", "-PGOSResetData",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraLarge"
        ]
        app.launch()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()
        app.buttons["add-habit"].tap()
        let name = app.textFields["habit-editor-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Water")
        app.segmentedControls.buttons["Multiple times per day"].tap()
        app.buttons["habit-editor-save"].tap()

        app.tabBars.buttons["Today"].tap()
        let decrease = app.buttons["today-habit-water-decrease"]
        let increase = app.buttons["today-habit-water-increase"]
        let count = app.staticTexts["today-habit-water-count"]
        XCTAssertTrue(increase.waitForExistence(timeout: 5))
        XCTAssertTrue(decrease.exists)
        XCTAssertFalse(decrease.isEnabled)

        increase.tap()
        increase.tap()
        increase.tap()
        XCTAssertEqual(count.value as? String, "3")
        decrease.tap()
        XCTAssertEqual(count.value as? String, "2")
        try performSemanticAccessibilityAudit(app)

        app.terminate()
        app.launchArguments = [
            "-PGOSUITesting",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraLarge"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["today-habit-water-count"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["today-habit-water-count"].value as? String, "2")
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
        app.segmentedControls.buttons["Multiple times per day"].tap()
        app.buttons["habit-editor-save"].tap()
        app.buttons["habit-reflect"].tap()
        app.buttons["habit-check-in-insight"].tap()

        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("Habit insight entry")
        app.buttons["capture-save"].tap()
        XCTAssertFalse(app.buttons["habit-check-in-undo"].exists)

        let increase = app.buttons["habit-detail-counter-increase"]
        let decrease = app.buttons["habit-detail-counter-decrease"]
        let count = app.staticTexts["habit-detail-counter-count"]
        XCTAssertTrue(increase.waitForExistence(timeout: 5))
        XCTAssertEqual(count.value as? String, "1")
        increase.tap()
        XCTAssertEqual(count.value as? String, "2")
        XCTAssertTrue(decrease.isEnabled)
        decrease.tap()
        XCTAssertEqual(count.value as? String, "1")

        let linkedEntry = app.staticTexts["Linked Entry"]
        for _ in 0..<6 where !linkedEntry.exists {
            app.swipeUp()
        }
        XCTAssertTrue(linkedEntry.exists)

        app.navigationBars.buttons["Habits"].tap()
        app.tabBars.buttons["Library"].tap()
        app.buttons["library-search-button"].tap()
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

        app.tabBars.buttons["Library"].tap()
        app.buttons["library-search-button"].tap()
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

        app.navigationBars.buttons["Library"].tap()
        app.buttons["library-search-button"].tap()
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

        for tab in ["今天", "时间线", "记录", "成长", "资料库"] {
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

        for tab in ["Today", "Timeline", "Record", "Growth", "Library"] {
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.buttons["quick-capture-button"].label.contains("Quick Capture"))
    }

    func testHabitDashboardLocalizesInSimplifiedChinese() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PGOSUITesting", "-PGOSResetData",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_Hans_CN"
        ]
        app.launch()

        app.tabBars.buttons["成长"].tap()
        app.buttons["growth-habits"].tap()
        app.buttons["add-habit"].tap()
        let name = app.textFields["habit-editor-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Localized Habit")
        app.buttons["habit-editor-save"].tap()

        let overviewCheckIn = app.buttons["habit-overview-check-in"]
        XCTAssertTrue(overviewCheckIn.waitForExistence(timeout: 5))
        overviewCheckIn.tap()
        app.buttons["habit-localized habit"].tap()

        XCTAssertTrue(app.staticTexts["当前"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["进度"].exists)
        XCTAssertTrue(app.staticTexts["状态"].exists)
        XCTAssertTrue(app.staticTexts["当前连续达成"].exists)
        XCTAssertTrue(app.staticTexts["最佳连续达成"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "1 天", "1 天"))
                .firstMatch.exists
        )
        XCTAssertEqual(app.buttons["habit-check-in"].label, "今日已完成")

        app.swipeUp()
        XCTAssertTrue(app.staticTexts["年度活动"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["趋势"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["星期规律"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["历程"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "已创建", "已创建"))
                .firstMatch.exists
        )
        XCTAssertTrue(app.staticTexts["最近活动"].exists)
    }

    func testMixedHabitRowsRemainAccessibleAcrossAppearanceAndTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PGOSUITesting", "-PGOSResetData",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()

        func addHabit(_ name: String, multiple: Bool = false, trackingOnly: Bool = false) {
            app.buttons["add-habit"].tap()
            let field = app.textFields["habit-editor-name"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(name)
            if multiple {
                app.segmentedControls.buttons["Multiple times per day"].tap()
            }
            if trackingOnly {
                app.buttons["habit-goal"].tap()
                app.buttons["No Goal"].tap()
            }
            app.buttons["habit-editor-save"].tap()
            XCTAssertTrue(app.buttons["add-habit"].waitForExistence(timeout: 5))
        }

        addHabit("Anchor Read")
        addHabit("Water", multiple: true)
        addHabit("Breathe", multiple: true)
        addHabit(
            "Observe one small detail with a deliberately long habit name",
            multiple: true,
            trackingOnly: true
        )

        let waterMinus = app.buttons["habit-overview-water-counter-decrease"]
        let waterPlus = app.buttons["habit-overview-water-counter-increase"]
        let waterCount = app.staticTexts["habit-overview-water-counter-count"]
        let breathePlus = app.buttons["habit-overview-breathe-counter-increase"]
        let trackingCount = app.staticTexts[
            "habit-overview-observe one small detail with a deliberately long habit name-counter-count"
        ]
        let longNameIncrease = app.buttons[
            "habit-overview-observe one small detail with a deliberately long habit name-counter-increase"
        ]
        XCTAssertTrue(waterPlus.waitForExistence(timeout: 5))
        XCTAssertTrue(breathePlus.exists)
        XCTAssertGreaterThanOrEqual(waterMinus.frame.width, 44)
        XCTAssertGreaterThanOrEqual(waterMinus.frame.height, 44)
        XCTAssertGreaterThanOrEqual(waterPlus.frame.width, 44)
        XCTAssertGreaterThanOrEqual(waterPlus.frame.height, 44)
        XCTAssertFalse(waterPlus.frame.intersects(breathePlus.frame))
        XCTAssertEqual(waterCount.value as? String, "0")

        waterPlus.tap()
        waterPlus.tap()
        waterPlus.tap()
        XCTAssertEqual(waterCount.value as? String, "3")
        try performSemanticAccessibilityAudit(app)
        if !trackingCount.exists {
            app.swipeUp()
        }
        XCTAssertTrue(trackingCount.waitForExistence(timeout: 5))
        XCTAssertEqual(trackingCount.value as? String, "0")
        if !longNameIncrease.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(longNameIncrease.waitForExistence(timeout: 5))
        XCTAssertTrue(longNameIncrease.isHittable)
        try performSemanticAccessibilityAudit(app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Build 8 mixed Habit rows"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPausedAndCompletedHabitsStayOutOfActiveScheduleSections() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PGOSUITesting", "-PGOSResetData",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()

        func addHabit(named habitName: String) {
            app.buttons["add-habit"].tap()
            let name = app.textFields["habit-editor-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText(habitName)
            app.buttons["habit-editor-save"].tap()
            XCTAssertTrue(app.buttons["add-habit"].waitForExistence(timeout: 5))
        }

        addHabit(named: "Pause Me")
        app.buttons["habit-pause me"].tap()
        app.buttons["habit-actions"].tap()
        app.buttons["Pause"].tap()
        app.navigationBars.buttons["Habits"].tap()

        addHabit(named: "Complete Me")
        app.buttons["habit-complete me"].tap()
        app.buttons["habit-actions"].tap()
        app.buttons["Complete"].tap()
        app.navigationBars.buttons["Habits"].tap()

        XCTAssertTrue(app.staticTexts["No Active Habits"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.staticTexts["habit-paused-pause me-status"].value as? String,
            "Paused"
        )
        XCTAssertEqual(
            app.staticTexts["habit-completed-complete me-status"].value as? String,
            "Completed"
        )
        XCTAssertFalse(app.staticTexts["0/1 today · 1 remaining"].exists)
        XCTAssertFalse(app.buttons["habit-overview-check-in"].exists)
    }

    func testHabitDetailNowPresentationFollowsLifecycle() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PGOSUITesting", "-PGOSResetData",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()

        func addHabit(named habitName: String) {
            app.buttons["add-habit"].tap()
            let name = app.textFields["habit-editor-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText(habitName)
            app.buttons["habit-editor-save"].tap()
            XCTAssertTrue(app.buttons["add-habit"].waitForExistence(timeout: 5))
        }

        func assertNoCurrentExpectation(status: String) {
            let statusValue = app.descendants(matching: .any)["habit-detail-status"]
            XCTAssertTrue(statusValue.waitForExistence(timeout: 5))
            XCTAssertTrue(
                statusValue.label.contains(status)
                    || (statusValue.value as? String)?.contains(status) == true
            )
            XCTAssertFalse(app.descendants(matching: .any)["habit-detail-current-progress"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["habit-detail-current-adherence"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["habit-detail-current-streak"].exists)
            XCTAssertFalse(app.buttons["habit-check-in"].exists)
            XCTAssertFalse(app.buttons["habit-log-details"].exists)
            XCTAssertFalse(app.buttons["habit-check-in-insight"].exists)
        }

        addHabit(named: "Active Detail")
        app.buttons["habit-active detail"].tap()
        let activeProgress = app.descendants(matching: .any)["habit-detail-current-progress"]
        XCTAssertTrue(activeProgress.waitForExistence(timeout: 5))
        XCTAssertTrue(
            activeProgress.label.contains("0/1 today")
                || (activeProgress.value as? String)?.contains("0/1 today") == true
        )
        XCTAssertTrue(app.descendants(matching: .any)["habit-detail-current-streak"].exists)
        XCTAssertTrue(app.buttons["habit-check-in"].exists)
        app.navigationBars.buttons["Habits"].tap()

        addHabit(named: "Paused Detail")
        app.buttons["habit-paused detail"].tap()
        app.buttons["habit-actions"].tap()
        app.buttons["Pause"].tap()
        assertNoCurrentExpectation(status: "Paused")
        app.navigationBars.buttons["Habits"].tap()

        addHabit(named: "Completed Detail")
        app.buttons["habit-completed detail"].tap()
        app.buttons["habit-actions"].tap()
        app.buttons["Complete"].tap()
        assertNoCurrentExpectation(status: "Completed")
    }

    func testOncePerDayEditorHidesSelectedDayTargetAndValidatesPeriodMaximum() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PGOSUITesting", "-PGOSResetData",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()
        app.buttons["add-habit"].tap()

        let name = app.textFields["habit-editor-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Bounded Plan")
        app.buttons["habit-goal"].tap()
        app.buttons["Selected Days"].tap()
        XCTAssertFalse(app.textFields["habit-daily-target"].exists)

        app.buttons["habit-goal"].tap()
        app.buttons["Times per Week"].tap()
        let target = app.textFields["habit-daily-target"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertEqual(target.label, "Weekly Target")
        target.tap()
        target.typeText("8")
        app.buttons["habit-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["Target must be between 1 and 7."].waitForExistence(timeout: 5))
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

    func testWeeklyReviewSavesMultipleFieldsAfterKeyboardDismissalAndPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PGOSUITesting", "-PGOSResetData",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()

        app.buttons["today-weekly-review"].tap()
        let weeklyReview = app.descendants(matching: .any)["weekly-review-view"]
        XCTAssertTrue(weeklyReview.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["start-weekly-review"].waitForExistence(timeout: 5))
        app.buttons["start-weekly-review"].tap()

        let remembered = app.descendants(matching: .any)["weekly-review-remembered"]
        XCTAssertTrue(remembered.waitForExistence(timeout: 5))
        remembered.tap()
        remembered.typeText("A useful moment")
        XCTAssertTrue(app.staticTexts["What do you want to remember?"].exists)

        let nextStep = app.descendants(matching: .any)["weekly-review-next-step"]
        XCTAssertTrue(nextStep.waitForExistence(timeout: 5))
        nextStep.tap()
        nextStep.typeText("Take one focused walk")
        let keyboardDone = app.buttons["weekly-review-keyboard-done"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5))
        keyboardDone.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["weekly-review-unsaved"]
                .waitForExistence(timeout: 5)
        )
        app.buttons["save-weekly-review"].tap()
        let saveConfirmation = app.descendants(matching: .any)["weekly-review-save-confirmation"]
        XCTAssertTrue(saveConfirmation.waitForExistence(timeout: 5))

        let completed = app.switches["weekly-review-completed"]
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertTrue(completed.isHittable)
        completed.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let completedExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1"),
            object: completed
        )
        XCTAssertEqual(XCTWaiter().wait(for: [completedExpectation], timeout: 5), .completed)
        XCTAssertTrue(saveConfirmation.waitForNonExistence(timeout: 5))
        app.buttons["save-weekly-review"].tap()
        XCTAssertTrue(saveConfirmation.waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["-PGOSUITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["today-weekly-review"].tap()

        let restoredNextStep = app.descendants(matching: .any)["weekly-review-next-step"]
        XCTAssertTrue(restoredNextStep.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredNextStep.value as? String, "Take one focused walk")
        XCTAssertEqual(
            app.descendants(matching: .any)["weekly-review-remembered"].value as? String,
            "A useful moment"
        )
        weeklyReview.swipeUp()
        let restoredCompleted = app.switches["weekly-review-completed"]
        XCTAssertTrue(restoredCompleted.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredCompleted.value as? String, "1")
    }

    func testLibraryHistoryAndSearchReopenTheSavedWeeklyReview() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PGOSUITesting", "-PGOSResetData",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()

        app.buttons["today-weekly-review"].tap()
        let startReview = app.buttons["start-weekly-review"]
        XCTAssertTrue(startReview.waitForExistence(timeout: 5))
        startReview.tap()
        let weeklyReview = app.descendants(matching: .any)["weekly-review-view"]
        let remembered = app.descendants(matching: .any)["weekly-review-remembered"]
        XCTAssertTrue(remembered.waitForExistence(timeout: 5))
        let saveReview = app.buttons["save-weekly-review"]
        for _ in 0..<4 where !saveReview.exists {
            weeklyReview.swipeUp()
        }
        XCTAssertTrue(saveReview.exists)
        XCTAssertFalse(saveReview.isEnabled)
        for _ in 0..<4 where !remembered.exists {
            weeklyReview.swipeDown()
        }
        XCTAssertTrue(remembered.exists)
        remembered.tap()
        remembered.typeText("Build Six history needle")
        app.buttons["weekly-review-keyboard-done"].tap()
        for _ in 0..<4 where !saveReview.exists {
            weeklyReview.swipeUp()
        }
        XCTAssertTrue(saveReview.isEnabled)
        saveReview.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["weekly-review-save-confirmation"]
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["Library"].tap()
        app.buttons["library-weekly-reviews"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["weekly-review-history"]
                .waitForExistence(timeout: 5)
        )
        app.staticTexts["Build Six history needle"].tap()
        XCTAssertEqual(
            app.descendants(matching: .any)["weekly-review-remembered"].value as? String,
            "Build Six history needle"
        )

        app.navigationBars.buttons["Weekly Reviews"].tap()
        app.navigationBars.buttons["Library"].tap()
        app.buttons["library-search-button"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("history needle")
        XCTAssertTrue(app.staticTexts["Weekly Reviews"].waitForExistence(timeout: 5))
        app.staticTexts["Build Six history needle"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["weekly-review-view"]
                .waitForExistence(timeout: 5)
        )
    }

    func testGrowthAddActionsRemainHittableWithDarkAppearanceAndLargeText() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PGOSUITesting", "-PGOSResetData",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraLarge"
        ]
        app.launch()

        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()
        XCTAssertTrue(app.buttons["add-habit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-habit"].isHittable)
        app.buttons["add-habit"].tap()
        let habitName = app.textFields["habit-editor-name"]
        XCTAssertTrue(habitName.waitForExistence(timeout: 5))
        habitName.tap()
        habitName.typeText("Stretch")
        app.buttons["habit-editor-save"].tap()
        XCTAssertTrue(app.buttons["add-habit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-habit"].isHittable)

        app.navigationBars.buttons["Growth"].tap()
        app.buttons["growth-weight"].tap()
        XCTAssertTrue(app.buttons["add-weight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-weight"].isHittable)
        app.buttons["add-weight"].tap()
        let weight = app.textFields["weight-editor-value"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        weight.tap()
        weight.typeText("70")
        app.buttons["weight-editor-save"].tap()
        XCTAssertTrue(app.buttons["add-weight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-weight"].isHittable)
    }
}
