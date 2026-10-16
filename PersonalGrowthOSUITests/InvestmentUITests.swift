import XCTest

final class InvestmentUITests: XCTestCase {
    func launch(chinese: Bool = false, darkLarge: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting","-PGOSResetData","-AppleLanguages",chinese ? "(zh-Hans)" : "(en)","-AppleLocale",chinese ? "zh_CN" : "en_US"]
        if darkLarge { app.launchArguments += ["-AppleInterfaceStyle","Dark","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch();return app
    }
    func reveal(_ element: XCUIElement,_ app: XCUIApplication) {
        for _ in 0..<10 { if element.isHittable {return};app.swipeUp() }
        XCTAssertTrue(element.isHittable,app.debugDescription)
    }
    func button(_ prefix: String,_ app: XCUIApplication) -> XCUIElement { app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@",prefix)).firstMatch }
    func openHub(_ app: XCUIApplication,chinese: Bool = false) {
        app.tabBars.buttons[chinese ? "成长" : "Growth"].tap()
        let entry=app.buttons["growth-investment"];reveal(entry,app);entry.tap()
        XCTAssertTrue(app.navigationBars[chinese ? "时间投入" : "Time investment"].waitForExistence(timeout:5))
        let intro=app.buttons[chinese ? "知道了" : "Got it"];if intro.exists {intro.tap()}
    }
    func create(_ app: XCUIApplication) {
        let field=app.textFields["investment-activity-name"];reveal(field,app);field.tap();field.typeText("Synthetic Reading")
        app.buttons["investment-create-activity"].tap()
        for _ in 0..<5 {app.swipeDown()}
    }
    func screenshot(_ app: XCUIApplication,_ name: String) {let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)}
    func testManualSaveHistoryNilFeelingEditAndDeleteRefreshSameReview() {
        let app=launch();openHub(app);create(app)
        let record=button("investment-record-",app);reveal(record,app);record.tap()
        let minutes=app.textFields["investment-duration"];XCTAssertTrue(minutes.waitForExistence(timeout:5))
        XCTAssertEqual(Double(minutes.value as? String ?? ""),45)
        let save=app.buttons["investment-save"];reveal(save,app);save.tap()
        let history=app.buttons["investment-history"];reveal(history,app);history.tap()
        XCTAssertTrue(app.staticTexts["investment-review-count"].waitForExistence(timeout:5))
        let row=button("investment-session-",app);reveal(row,app);row.tap()
        XCTAssertTrue(app.staticTexts["Experience not filled"].waitForExistence(timeout:5))
        let edit=app.buttons["investment-edit-session"];reveal(edit,app);edit.tap()
        let note=app.textFields["investment-note"];reveal(note,app);note.tap();note.typeText("Synthetic edited experience")
        if app.buttons["Done"].exists {app.buttons["Done"].tap()}
        let editedSave=app.buttons["investment-save"];reveal(editedSave,app);editedSave.tap()
        XCTAssertTrue(app.staticTexts["Synthetic edited experience"].waitForExistence(timeout:5))
        let delete=app.buttons["investment-delete-session"];reveal(delete,app);delete.tap();app.sheets.buttons["Delete record"].tap()
        XCTAssertTrue(app.staticTexts["No records in this selection"].waitForExistence(timeout:5))
    }
    func testTimerForegroundBackgroundFrozenConfirmationAndColdRelaunch() {
        let app=launch();openHub(app);create(app)
        let start=button("investment-start-",app);reveal(start,app);start.tap()
        XCTAssertTrue(app.buttons["investment-pause"].waitForExistence(timeout:5))
        XCUIDevice.shared.press(.home);app.activate()
        app.buttons["investment-pause"].tap();app.buttons["investment-resume"].tap();app.buttons["investment-finish"].tap()
        XCTAssertTrue(app.buttons["investment-save"].waitForExistence(timeout:5))
        screenshot(app,"Investment-English-frozen-confirmation")
        let keep=app.buttons["Close and keep pending"];reveal(keep,app);keep.tap()
        app.buttons["investment-resume"].tap();app.buttons["investment-finish"].tap()
        XCTAssertTrue(app.buttons["investment-save"].waitForExistence(timeout:5))
        app.terminate();app.launchArguments.removeAll {$0 == "-PGOSResetData"};app.launch()
        let today=app.buttons["today-investment"];reveal(today,app);today.tap()
        let pending=app.buttons["investment-unfinished"];reveal(pending,app);pending.tap()
        XCTAssertTrue(app.staticTexts["investment-timer-state"].label.contains("Finished"))
        app.buttons["investment-review-save"].tap();let save=app.buttons["investment-save"];reveal(save,app);save.tap()
        XCTAssertFalse(app.staticTexts["investment-save-error"].exists)
    }
    func testRecordDraftSurvivesManualActivitySaveAndChineseDarkAX() {
        let app=launch(chinese:true,darkLarge:true)
        app.tabBars.buttons["记录"].tap();let body=app.textViews["capture-body"];body.tap();body.typeText("Synthetic independent Record draft")
        openHub(app,chinese:true);create(app)
        let record=button("investment-record-",app);reveal(record,app);record.tap()
        screenshot(app,"Investment-Chinese-Dark-AX-editor")
        let save=app.buttons["investment-save"];reveal(save,app);save.tap()
        app.tabBars.buttons["记录"].tap();XCTAssertEqual(body.value as? String,"Synthetic independent Record draft")
        screenshot(app,"Investment-Record-draft-retained")
    }
}
