import XCTest

final class SleepUITests: XCTestCase {
    private func launch(chinese: Bool = false, controls: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "-AppleInterfaceStyle", "Light"]
        if controls { app.launchArguments += ["-PGOSSleepRouteControlsTest"] }
        app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func openToday(_ app: XCUIApplication) {
        let entry = app.buttons["today-sleep"]; reveal(entry, app: app); entry.tap()
        XCTAssertTrue(app.staticTexts["sleep-wake-day"].waitForExistence(timeout: 5))
    }
    private func attachment(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testMorningThreeChoicesSaveRestartReviewEditDeleteAndWeightFocus() {
        let app = launch(); openToday(app)
        XCTAssertFalse(app.buttons["sleep-save"].isEnabled); XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["sleep-bed-menu"].tap(); app.buttons["sleep-bed-1380-30"].tap()
        app.buttons["sleep-wake-menu"].tap(); app.buttons["sleep-wake-420-15"].tap()
        app.buttons["sleep-feeling-4"].tap()
        XCTAssertTrue(app.buttons["sleep-save"].isHittable)
        attachment(app, "Sleep-English-three-choices")
        app.buttons["sleep-save"].tap()
        XCTAssertTrue(app.buttons["today-sleep"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["today-sleep"].label.contains("23:00"))
        app.terminate(); app.launchArguments.removeAll { $0 == "-PGOSResetData" }; app.launch()
        openToday(app)
        XCTAssertTrue(app.buttons["sleep-bed-menu"].label.contains("23:00–23:30"))
        XCTAssertTrue(app.buttons["sleep-wake-menu"].label.contains("07:00–07:15"))
        XCTAssertTrue(app.buttons["sleep-feeling-4"].isSelected)
        app.buttons["sleep-feeling-3"].tap(); app.buttons["sleep-save"].tap()
        app.tabBars.buttons["Growth"].tap(); app.buttons["growth-sleep"].tap(); app.buttons["sleep-review"].tap()
        XCTAssertTrue(app.staticTexts["1 recorded wake days / 7 calendar days"].waitForExistence(timeout: 5))
        let plotted = app.buttons["Open plotted nights"]
        reveal(plotted, app: app)
        attachment(app, "Sleep-seven-day-visible-interval-chart")
        plotted.tap()
        XCTAssertTrue(app.navigationBars["Original sleep records"].waitForExistence(timeout: 5))
        let source = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "[0-9]{4}-[0-9]{2}-[0-9]{2}")).firstMatch
        XCTAssertTrue(source.isHittable); source.tap()
        XCTAssertTrue(app.buttons["sleep-bed-menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sleep-bed-menu"].label.contains("23:00–23:30"))
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let night = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sleep-review-night-")).firstMatch
        reveal(night, app: app); XCTAssertTrue(night.label.contains("7 h 30 min–8 h 15 min")); night.tap()
        let delete = app.buttons["sleep-delete"]; reveal(delete, app: app); delete.tap()
        app.sheets.buttons["Delete sleep record"].tap()
        for _ in 0..<5 { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["0 recorded wake days / 7 calendar days"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
        let weight = app.buttons["today-add-weight"]; reveal(weight, app: app); weight.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        attachment(app, "Weight-direct-focus-after-sleep")
    }
    func testCancelBackgroundAndRecordTabDraftRemainIndependent() {
        let app = launch(controls: true); openToday(app)
        app.buttons["sleep-feeling-5"].tap(); app.buttons["Cancel"].tap()
        openToday(app); XCTAssertTrue(app.buttons["sleep-feeling-5"].isSelected)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["sleep-feeling-5"].isSelected)
        app.buttons["sleep-save"].tap()
        app.tabBars.buttons["Record"].tap()
        let body = app.textViews["capture-body"]; body.tap(); body.typeText("Synthetic record draft retained")
        app.buttons["sleep-test-route"].tap()
        XCTAssertTrue(app.staticTexts["sleep-wake-day"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertEqual(body.value as? String, "Synthetic record draft retained")
        app.buttons["capture-save"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic record draft retained"].waitForExistence(timeout: 5))
    }
    func testChineseDarkLargeTextPartialSaveAndSettingsRemainUsable() throws {
        let app = launch(chinese: true)
        app.terminate(); app.launchArguments.removeLast(2); app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"]; app.launch()
        openToday(app)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let feeling = app.buttons["sleep-feeling-2"]; reveal(feeling, app: app); feeling.tap()
        let save = app.buttons["sleep-save"]; reveal(save, app: app)
        attachment(app, "Sleep-Chinese-dark-AX-partial")
        save.tap(); app.tabBars.buttons["成长"].tap(); app.buttons["growth-sleep"].tap()
        let settings = app.buttons["sleep-settings"]; reveal(settings, app: app); settings.tap()
        let reminder = app.switches["sleep-reminder-enabled"]; reveal(reminder, app: app)
        attachment(app, "Sleep-Chinese-dark-AX-settings")
        XCTAssertTrue(app.staticTexts["sleep-reminder-status"].exists)
    }
}

extension SleepUITests {
    func testExpiredNotificationDateProtectsRecordAndImportantDayDrafts() {
        let app = XCUIApplication(); continueAfterFailure = false
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSSleepRouteControlsTest", "-PGOSSleepQueueOnBackgroundTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); app.tabBars.buttons["Record"].tap()
        let body = app.textViews["capture-body"]; body.tap(); body.typeText("Synthetic route-protected Record draft")
        app.buttons["sleep-test-route"].tap()
        XCTAssertTrue(app.staticTexts["sleep-wake-day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["sleep-wake-day"].label.contains("2026-01-01"))
        app.buttons["Cancel"].tap()
        XCTAssertEqual(body.value as? String, "Synthetic route-protected Record draft")
        app.tabBars.buttons["Growth"].tap(); app.buttons["growth-important-days"].tap(); app.buttons["important-day-add"].tap()
        let title = app.textFields["important-day-title"]; title.tap(); title.typeText("Synthetic protected day draft")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(title.value as? String, "Synthetic protected day draft")
        XCTAssertFalse(app.staticTexts["sleep-wake-day"].exists)
        app.buttons["Cancel"].tap(); app.buttons["sleep-pending-route"].tap()
        XCTAssertTrue(app.staticTexts["sleep-wake-day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["sleep-wake-day"].label.contains("2026-01-01"))
        app.buttons["Cancel"].tap(); app.tabBars.buttons["Record"].tap()
        XCTAssertEqual(body.value as? String, "Synthetic route-protected Record draft")
    }
    func testColdSleepRouteWaitsForRecoveryAndOpensItsOriginalDay() {
        let app = XCUIApplication(); continueAfterFailure = false
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSSleepColdRouteTest", "-PGOSStartupFailureTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.otherElements["startup-error"].waitForExistence(timeout: 5) || app.staticTexts["startup-diagnostic"].exists)
        XCTAssertFalse(app.staticTexts["sleep-wake-day"].exists); XCTAssertFalse(app.tabBars.firstMatch.exists)
        app.buttons["startup-retry"].tap()
        XCTAssertTrue(app.staticTexts["sleep-wake-day"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["sleep-wake-day"].label.contains("2026-01-01"))
        app.buttons["Cancel"].tap(); app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["Preserved startup retry fixture"].waitForExistence(timeout: 5))
    }
}

extension SleepUITests {
    func testGoalVisibilityAndDeniedReminderRemainIndependentOfSavedFacts() {
        let app = XCUIApplication(); continueAfterFailure = false
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSTodoReminderDeniedTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", "Light"]
        app.launch(); openToday(app); app.buttons["sleep-feeling-3"].tap(); app.buttons["sleep-save"].tap()
        app.tabBars.buttons["Growth"].tap(); app.buttons["growth-sleep"].tap(); app.buttons["sleep-settings"].tap()
        app.switches["sleep-goal-enabled"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(app.switches["sleep-goal-enabled"].value as? String, "1")
        app.buttons["sleep-save-goal"].tap()
        XCTAssertTrue(app.otherElements["sleep-save-feedback"].waitForExistence(timeout: 5) || app.staticTexts["Bedtime goal saved."].exists)
        app.switches["sleep-show-today"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(app.switches["sleep-show-today"].value as? String, "0")
        let reminder = app.switches["sleep-reminder-enabled"]; reveal(reminder, app: app); reminder.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(reminder.value as? String, "1")
        let status = app.staticTexts["sleep-reminder-status"]; reveal(status, app: app)
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "disabled in iOS Settings"), object: status)], timeout: 5), .completed, status.label)
        attachment(app, "Sleep-actual-enabled-goal-hidden-entry-denied-reminder")
        app.tabBars.buttons["Today"].tap(); XCTAssertFalse(app.buttons["today-sleep"].exists)
        app.tabBars.buttons["Growth"].tap()
        XCTAssertEqual(app.switches["sleep-reminder-enabled"].value as? String, "1")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sleep-history-")).count, 1)
    }
}

extension SleepUITests {
    func testR1ReviewEditsImmediatelyKeepTimeAndFeelingSamplesWithoutLeavingReview() {
        let app = launch(); openToday(app)
        app.buttons["sleep-bed-menu"].tap(); app.buttons["sleep-bed-1380-30"].tap()
        app.buttons["sleep-wake-menu"].tap(); app.buttons["sleep-wake-420-15"].tap()
        app.buttons["sleep-feeling-4"].tap(); app.buttons["sleep-save"].tap()
        app.tabBars.buttons["Growth"].tap(); app.buttons["growth-sleep"].tap(); app.buttons["sleep-review"].tap()
        XCTAssertTrue(app.staticTexts["1 recorded wake days / 7 calendar days"].waitForExistence(timeout: 5))
        let night = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sleep-review-night-")).firstMatch
        reveal(night, app: app); night.tap()
        app.buttons["sleep-bed-menu"].tap(); app.buttons["sleep-bed-1410-30"].tap()
        app.buttons["sleep-wake-menu"].tap(); app.buttons["sleep-wake-435-15"].tap()
        app.buttons["sleep-feeling-2"].tap(); app.buttons["sleep-save"].tap()
        XCTAssertTrue(app.navigationBars["Sleep review"].waitForExistence(timeout: 5))
        for _ in 0..<4 { app.swipeDown() }
        let samples = app.staticTexts["Bedtime samples: 1 · Getting-up samples: 1 · Interval samples: 1"]
        reveal(samples, app: app); XCTAssertTrue(samples.exists, app.debugDescription)
        let ratings = app.staticTexts["Valid ratings: 1"]; reveal(ratings, app: app)
        XCTAssertTrue(ratings.exists, app.debugDescription)
        attachment(app, "R1-immediate-review-after-real-edit")
        let poor = app.buttons["sleep-review-feeling-2"]; reveal(poor, app: app); poor.tap()
        let source = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sleep-source-night-")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5)); source.tap()
        app.buttons["sleep-feeling-5"].tap(); app.buttons["sleep-save"].tap()
        XCTAssertTrue(app.staticTexts["No matching sleep records."].waitForExistence(timeout: 5), app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<4 { app.swipeDown() }
        let plotted = app.buttons["Open plotted nights"]; reveal(plotted, app: app); plotted.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5)); source.tap()
        app.buttons["sleep-wake-menu"].tap(); app.buttons["Unknown"].tap(); app.buttons["sleep-save"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<4 { app.swipeDown() }
        let partial = app.staticTexts["Bedtime samples: 1 · Getting-up samples: 0 · Interval samples: 0"]
        reveal(partial, app: app); XCTAssertTrue(partial.exists, app.debugDescription)
        for _ in 0..<4 { app.swipeDown() }
        app.segmentedControls.buttons["30 days"].tap()
        XCTAssertTrue(app.staticTexts["1 recorded wake days / 30 calendar days"].waitForExistence(timeout: 5))
        attachment(app, "R1-plot-source-edit-and-thirty-day-review")
    }
    func testR2SavingInitiallyOffGoalDoesNotConsumeFirstTodayActivationInSettings() {
        let app = launch()
        app.tabBars.buttons["Growth"].tap(); app.buttons["growth-sleep"].tap(); app.buttons["sleep-settings"].tap()
        let enabled = app.switches["sleep-goal-enabled"]
        XCTAssertEqual(enabled.value as? String, "0")
        app.buttons["sleep-save-goal"].tap()
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Goal disabled")).firstMatch.exists, app.debugDescription)
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(enabled.value as? String, "1")
        app.buttons["sleep-save-goal"].tap()
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        XCTAssertTrue(app.staticTexts[formatter.string(from: Date()) + " · 23:30"].waitForExistence(timeout: 5), app.debugDescription)
        attachment(app, "R2-first-enabled-goal-after-off-save")
        app.terminate(); app.launchArguments.removeAll { $0 == "-PGOSResetData" }; app.launch()
        app.tabBars.buttons["Growth"].tap(); app.buttons["growth-sleep"].tap(); app.buttons["sleep-settings"].tap()
        XCTAssertEqual(app.switches["sleep-goal-enabled"].value as? String, "1")
    }
}
