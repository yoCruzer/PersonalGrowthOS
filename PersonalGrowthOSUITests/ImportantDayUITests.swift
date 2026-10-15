import XCTest
import Darwin

final class ImportantDayUITests: XCTestCase {
    private func launch(seed: Bool = false, chinese: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        if seed { app.launchArguments += ["-PGOSImportantDaysTest"] }
        app.launch(); return app
    }
    private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func acceptSystemOpenIfNeeded(_ app: XCUIApplication) {
        let predicate = NSPredicate(format: "label == %@ OR label == %@", "Open", "打开")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let systemOpen = springboard.buttons.matching(predicate).firstMatch
        if systemOpen.waitForExistence(timeout: 5) { systemOpen.tap() }
        else {
            let open = app.buttons.matching(predicate).firstMatch
            if open.waitForExistence(timeout: 2) { open.tap() }
        }
    }
    func testMinimalCreateWriteRelatedEntryAndRelaunch() {
        let app = launch()
        app.tabBars.buttons["Growth"].tap(); app.buttons["growth-important-days"].tap()
        XCTAssertTrue(app.otherElements["important-days-list"].waitForExistence(timeout: 5) || app.navigationBars["Important Days"].exists)
        app.buttons["important-day-add"].tap()
        let title = app.textFields["important-day-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("A synthetic day")
        XCTAssertTrue(app.buttons["important-day-save"].isEnabled); app.buttons["important-day-save"].tap()
        app.staticTexts["A synthetic day"].firstMatch.tap()
        app.buttons["important-day-write"].tap()
        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5)); body.tap(); body.typeText("A related entry written today")
        app.buttons["capture-save"].tap()
        XCTAssertTrue(app.staticTexts["A related entry written today"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments.removeAll { $0 == "-PGOSResetData" }; app.launch()
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["A related entry written today"].waitForExistence(timeout: 5))
        app.staticTexts["A related entry written today"].tap()
        let link = app.staticTexts["A synthetic day"].firstMatch; scrollTo(link, app: app); link.tap()
        XCTAssertTrue(app.buttons["important-day-write"].waitForExistence(timeout: 5))
    }
    func testOldEntryCreationRequiresActualOccurrenceConfirmation() {
        let app = launch(seed: true)
        app.tabBars.buttons["Timeline"].tap(); app.staticTexts["Synthetic memory"].firstMatch.tap()
        let create = app.buttons["entry-create-important-day"]; scrollTo(create, app: app); create.tap()
        XCTAssertTrue(app.textFields["important-day-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["important-day-save"].isEnabled)
        let confirm = app.switches["important-day-confirm-occurrence"]; scrollTo(confirm, app: app); confirm.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(confirm.value as? String, "1")
        XCTAssertTrue(app.buttons["important-day-save"].isEnabled)
        app.buttons["important-day-save"].tap()
        XCTAssertTrue(app.buttons["entry-create-important-day"].waitForExistence(timeout: 5))
    }
    func testWidgetRoutePreservesRecordDraftAndQueuesBehindAnExistingEditor() {
        let app = launch(seed: true)
        app.tabBars.buttons["Record"].tap()
        let body = app.textViews["capture-body"]; body.tap(); body.typeText("Record draft survives widget route")
        print("PGOS_ROUTE_UI_READY_1"); fflush(stdout)
        acceptSystemOpenIfNeeded(app)
        XCTAssertTrue(app.buttons["important-day-write"].waitForExistence(timeout: 30))
        app.navigationBars.buttons["Done"].firstMatch.tap()
        XCTAssertEqual(body.value as? String, "Record draft survives widget route")
        app.tabBars.buttons["Growth"].tap(); app.buttons["growth-important-days"].tap()
        app.buttons["important-day-add"].tap()
        let title = app.textFields["important-day-title"]; title.tap(); title.typeText("Unfinished day editor")
        print("PGOS_ROUTE_UI_READY_2"); fflush(stdout)
        acceptSystemOpenIfNeeded(app)
        XCTAssertTrue(app.staticTexts["important-day-editor-route-queued"].waitForExistence(timeout: 30))
        XCTAssertTrue(title.exists); XCTAssertEqual(title.value as? String, "Unfinished day editor")
        XCTAssertFalse(app.staticTexts["Day unavailable"].exists)
        app.buttons["Cancel"].firstMatch.tap()
        let pending = app.buttons["important-day-pending-route"]
        XCTAssertTrue(pending.waitForExistence(timeout: 5)); pending.tap()
        XCTAssertTrue(app.staticTexts["Day unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This day was removed, archived or is no longer authorized for desktop display."].exists)
        app.navigationBars.buttons["Done"].firstMatch.tap()
        app.tabBars.buttons["Record"].tap(); XCTAssertEqual(body.value as? String, "Record draft survives widget route")
    }
    func testChineseDarkLargeTextShowsDaysAndPresets() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSImportantDaysTest", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.tabBars.buttons["成长"].tap()
        let days = app.buttons["growth-important-days"]; scrollTo(days, app: app); days.tap()
        XCTAssertTrue(app.navigationBars["重要日子"].waitForExistence(timeout: 5))
        app.buttons["important-day-add"].tap()
        XCTAssertTrue(app.textFields["important-day-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["期待某一天"].exists)
        app.swipeUp()
        XCTAssertTrue(app.pickerWheels.firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "important-day-zh-dark-AXXXL"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
