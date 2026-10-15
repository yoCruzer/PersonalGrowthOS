import XCTest

final class ImportantDayReviewFixUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSImportantDaysTest", "-PGOSImportantDaysReviewTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); return app
    }
    private func openDay(_ title: String, app: XCUIApplication) {
        app.tabBars.buttons["Growth"].tap(); app.buttons["growth-important-days"].tap()
        app.staticTexts[title].firstMatch.tap()
    }
    private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<10 {
            if element.isHittable { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.82)).press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.25)))
        }
        XCTAssertTrue(element.isHittable)
    }
    private func enableDefaultPeriod(_ app: XCUIApplication) {
        let toggle = app.switches["important-day-explicit-period"]; scrollTo(toggle, app: app)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertEqual(app.pickerWheels.firstMatch.value as? String, "2026")
    }
    func testDefaultPeriodAcrossSyntheticDayRefreshUsesAllThreeRealEntrances() {
        for kind in ["write", "link", "todo"] {
            let app = launch(); openDay("Review annual", app: app); enableDefaultPeriod(app)
            let action = app.buttons["important-day-" + kind]; scrollTo(action, app: app); action.tap()
            let period = app.staticTexts["important-day-operation-period"]
            XCTAssertTrue(period.waitForExistence(timeout: 5)); XCTAssertEqual(period.label, "Selected date: 2026-10-15")
            app.buttons["important-day-test-advance"].tap()
            XCTAssertEqual(period.label, "Selected date: 2026-10-15")
            if kind == "write" {
                let body = app.textViews["capture-body"]; body.tap(); body.typeText("Written for frozen default year")
                app.buttons["capture-save"].tap()
            } else if kind == "link" {
                app.staticTexts["Existing review memory"].firstMatch.tap()
            } else {
                let title = app.textFields["todo-title"]; title.tap(); title.typeText("Todo for frozen default year")
                app.buttons["todo-save"].tap()
            }
            XCTAssertTrue(app.buttons["important-day-write"].waitForExistence(timeout: 5))
            if kind == "todo" {
                let todo = app.staticTexts["Todo for frozen default year"]; scrollTo(todo, app: app); XCTAssertTrue(todo.exists)
            } else {
                let filter = app.buttons["important-day-period-filter"]; scrollTo(filter, app: app); filter.tap()
                app.buttons["2026-10-15"].firstMatch.tap()
                let saved = app.staticTexts[kind == "write" ? "Written for frozen default year" : "Existing review memory"].firstMatch
                XCTAssertTrue(saved.exists)
            }
            app.terminate()
        }
    }
    func testDateChangeRequiresConfirmationAndPreservesCaptureDraft() {
        let app = launch(); openDay("Review annual", app: app); enableDefaultPeriod(app)
        let write = app.buttons["important-day-write"]; scrollTo(write, app: app); write.tap()
        let body = app.textViews["capture-body"]; body.tap(); body.typeText("Keep this draft through confirmation")
        app.buttons["important-day-test-change-rule"].tap()
        XCTAssertTrue(app.staticTexts["important-day-operation-confirmation"].waitForExistence(timeout: 5))
        app.buttons["capture-save"].tap()
        XCTAssertTrue(app.staticTexts["capture-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "Keep this draft through confirmation")
        app.buttons["Confirm this association and keep my draft"].tap()
        XCTAssertEqual(body.value as? String, "Keep this draft through confirmation")
        XCTAssertEqual(app.staticTexts["important-day-operation-period"].label, "Selected date: 2026-10-16")
        app.buttons["capture-save"].tap()
        let filter = app.buttons["important-day-period-filter"]; scrollTo(filter, app: app); filter.tap()
        app.buttons["2026-10-16"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Keep this draft through confirmation"].exists)
    }
    func testUnlinkLastSpecificPeriodImmediatelyShowsGeneralEntriesOnSamePage() {
        let app = launch(); openDay("Review annual", app: app)
        let filter = app.buttons["important-day-period-filter"]; scrollTo(filter, app: app); filter.tap()
        app.buttons["2026-10-15"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["General A"].exists)
        let period = app.staticTexts["Period 2026"].firstMatch; period.swipeLeft(); app.buttons["Unlink"].tap()
        XCTAssertTrue(app.staticTexts["General A"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["General B"].firstMatch.exists)
        XCTAssertFalse(filter.exists)
    }
    func testLunarLeapCalendarConfirmationCancelThenSaveAndReopen() {
        let app = launch(); openDay("Review lunar leap", app: app)
        func edit() {
            let button = app.buttons["Edit Important Day"]; scrollTo(button, app: app); button.tap()
            XCTAssertFalse(app.buttons["Use the date in the selected calendar"].exists)
            XCTAssertTrue(app.buttons["important-day-save"].isEnabled)
            XCTAssertTrue(app.staticTexts["important-day-preview"].label.contains("elapsed"))
        }
        edit()
        app.buttons["important-day-calendar"].tap(); app.buttons["Gregorian"].tap()
        app.buttons["Use the date in the selected calendar"].tap(); XCTAssertTrue(app.buttons["important-day-save"].isEnabled)
        app.buttons["Cancel"].firstMatch.tap()
        edit()
        let leap = app.switches["Lunar leap month"]; scrollTo(leap, app: app); XCTAssertEqual(leap.value as? String, "1")
        for _ in 0..<3 { app.swipeDown() }
        app.buttons["important-day-calendar"].tap(); app.buttons["Gregorian"].tap()
        app.buttons["Use the date in the selected calendar"].tap(); XCTAssertTrue(app.buttons["important-day-save"].isEnabled)
        app.buttons["important-day-save"].tap()
        app.terminate(); app.launchArguments.removeAll { $0 == "-PGOSResetData" }; app.launch()
        openDay("Review lunar leap", app: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Gregorian · 2023", "2/1")).firstMatch.exists)
        let button = app.buttons["Edit Important Day"]; scrollTo(button, app: app); button.tap()
        XCTAssertFalse(app.buttons["Use the date in the selected calendar"].exists)
        XCTAssertTrue(app.buttons["important-day-save"].isEnabled)
        XCTAssertFalse(app.switches["Lunar leap month"].exists)
    }
    func testSearchSubsetExplainsDisabledReorderAndClearsWithoutChangingFavorites() {
        let app = launch()
        app.tabBars.buttons["Growth"].tap(); app.buttons["growth-important-days"].tap()
        app.buttons["Edit"].tap()
        let search = app.searchFields.firstMatch
        if !search.isHittable { app.swipeDown() }
        search.tap(); search.typeText("pair\n")
        XCTAssertTrue(app.staticTexts["important-day-reorder-search-note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review C"].exists); XCTAssertTrue(app.staticTexts["Review D"].exists)
        XCTAssertFalse(app.staticTexts["Review annual"].exists)
        search.tap(); search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        XCTAssertFalse(app.staticTexts["important-day-reorder-search-note"].exists)
        XCTAssertTrue(app.staticTexts["Review annual"].exists)
        XCTAssertTrue(app.staticTexts["Review lunar leap"].exists)
    }
}
