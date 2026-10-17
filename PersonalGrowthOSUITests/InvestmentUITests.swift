import XCTest

final class InvestmentUITests: XCTestCase {
    func launch(chinese: Bool = false, darkLarge: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting","-PGOSResetData","-AppleLanguages",chinese ? "(zh-Hans)" : "(en)","-AppleLocale",chinese ? "zh_CN" : "en_US"]
        app.launchArguments += ["-AppleInterfaceStyle",darkLarge ? "Dark" : "Light",
                                "-UIPreferredContentSizeCategoryName",darkLarge ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch();return app
    }
    func reveal(_ element: XCUIElement,_ app: XCUIApplication,avoidingWheel: Bool = false) {
        for _ in 0..<10 {
            if element.isHittable {return}
            if avoidingWheel {
                // The observed wheel occupies x=41...361 in a 402pt Form. Scroll its outer gutter.
                app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:0.80)).press(forDuration:0.05,
                    thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:0.30)))
            } else {app.swipeUp()}
        }
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
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout:5))
        for _ in 0..<5 {app.swipeDown()}
    }
    func screenshot(_ app: XCUIApplication,_ name: String) {let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)}
    func testManualSaveHistoryNilFeelingEditAndDeleteRefreshSameReview() {
        let app=launch();openHub(app);create(app)
        let record=button("investment-record-",app);reveal(record,app);record.tap()
        let minutes=app.textFields["investment-duration"];XCTAssertTrue(minutes.waitForExistence(timeout:5))
        XCTAssertEqual(Double(minutes.value as? String ?? ""),45)
        let save=app.buttons["investment-save"];reveal(save,app);save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout:5))
        let history=app.buttons["investment-history"];reveal(history,app);history.tap()
        XCTAssertTrue(app.navigationBars["History and review"].waitForExistence(timeout:5))
        let count = app.staticTexts["investment-review-count"]
        XCTAssertTrue(count.waitForExistence(timeout:5))
        XCTAssertTrue(count.label.contains("1"), count.label)
        XCTAssertTrue(app.staticTexts["investment-review-total"].label.contains("0:45:00"))
        let day = button("investment-day-",app); reveal(day,app); day.tap()
        screenshot(app,"Investment-English-day-contribution-and-history")
        let row=button("investment-session-",app);reveal(row,app);row.tap()
        XCTAssertTrue(app.staticTexts["Experience not filled"].waitForExistence(timeout:5))
        let edit=app.buttons["investment-edit-session"];reveal(edit,app);edit.tap()
        let editedMinutes=app.textFields["investment-duration"]; reveal(editedMinutes,app); editedMinutes.tap()
        let old = editedMinutes.value as? String ?? ""
        editedMinutes.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+"30")
        app.buttons["Done"].tap()
        let note=app.textFields["investment-note"];reveal(note,app);note.tap();note.typeText("Synthetic edited experience")
        if app.buttons["Done"].exists {app.buttons["Done"].tap()}
        let editedSave=app.buttons["investment-save"];reveal(editedSave,app);editedSave.tap()
        XCTAssertTrue(app.staticTexts["Synthetic edited experience"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["0:30:00"].exists)
        app.navigationBars.buttons.element(boundBy:0).tap()
        for _ in 0..<5 {app.swipeDown()}
        let period=app.segmentedControls["investment-review-period"]
        for title in ["7 days","30 days","All time"] {
            period.buttons[title].tap()
            XCTAssertTrue(app.staticTexts["investment-review-total"].label.contains("0:30:00"))
            XCTAssertTrue(app.staticTexts["investment-review-count"].label.contains("1"))
        }
        screenshot(app,"Investment-English-edited-review-thirty-minutes")
        let editedRow=button("investment-session-",app);reveal(editedRow,app);editedRow.tap()
        let delete=app.buttons["investment-delete-session"];reveal(delete,app);delete.tap();app.sheets.buttons["Delete record"].tap()
        XCTAssertTrue(app.staticTexts["No records in this selection"].waitForExistence(timeout:5))
        for _ in 0..<5 {app.swipeDown()}
        XCTAssertTrue(app.staticTexts["investment-review-count"].label.contains("0"))
        XCTAssertTrue(app.staticTexts["investment-review-total"].label.contains("0:00:00"))
    }
    func testTimerForegroundBackgroundFrozenConfirmationAndColdRelaunch() {
        let app=launch();openHub(app);create(app)
        let start=button("investment-start-",app);reveal(start,app);start.tap()
        XCTAssertTrue(app.buttons["investment-pause"].waitForExistence(timeout:5))
        XCUIDevice.shared.press(.home);app.activate()
        let pause=app.buttons["investment-pause"];reveal(pause,app);pause.tap()
        XCTAssertTrue(app.staticTexts["investment-timer-state"].label.contains("Timer paused"))
        XCTAssertFalse(app.buttons["investment-save"].exists)
        let resume=app.buttons["investment-resume"];reveal(resume,app);resume.tap()
        XCTAssertTrue(app.staticTexts["investment-timer-state"].label.contains("Timer running"))
        XCTAssertFalse(app.buttons["investment-save"].exists)
        let finish=app.buttons["investment-finish"];reveal(finish,app);finish.tap()
        XCTAssertTrue(app.buttons["investment-save"].waitForExistence(timeout:5))
        screenshot(app,"Investment-English-frozen-confirmation")
        let keep=app.buttons["Close and keep pending"];reveal(keep,app);keep.tap()
        let pendingResume=app.buttons["investment-resume"];reveal(pendingResume,app);pendingResume.tap()
        XCTAssertTrue(app.staticTexts["investment-timer-state"].label.contains("Timer running"))
        let finishAgain=app.buttons["investment-finish"];reveal(finishAgain,app);finishAgain.tap()
        XCTAssertTrue(app.buttons["investment-save"].waitForExistence(timeout:5))
        app.terminate();app.launchArguments.removeAll {$0 == "-PGOSResetData"};app.launch()
        let today=app.buttons["today-investment"];reveal(today,app);today.tap()
        let pending=app.buttons["investment-unfinished"];reveal(pending,app);pending.tap()
        XCTAssertTrue(app.staticTexts["investment-timer-state"].label.contains("Finished"))
        app.buttons["investment-review-save"].tap();let save=app.buttons["investment-save"];reveal(save,app);save.tap()
        XCTAssertFalse(app.staticTexts["investment-save-error"].exists)
    }
    func testRecordDraftSurvivesManualActivitySaveAndChineseDarkAX() throws {
        let app=launch(chinese:true,darkLarge:true)
        app.tabBars.buttons["记录"].tap();let body=app.textViews["capture-body"];body.tap();body.typeText("Synthetic independent Record draft")
        body.swipeDown()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout:5))
        openHub(app,chinese:true);create(app)
        let record=button("investment-record-",app);reveal(record,app);record.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","投入活动")).firstMatch.exists)
        XCTAssertGreaterThanOrEqual(app.pickerWheels.count,3)
        let dateParts=(0..<3).map { index in
            Int((app.pickerWheels.element(boundBy:index).value as? String ?? "").prefix(while:{$0.isNumber}))
        }
        let originalDay=String(format:"%04d-%02d-%02d",try XCTUnwrap(dateParts[0]),try XCTUnwrap(dateParts[1]),try XCTUnwrap(dateParts[2]))
        screenshot(app,"Investment-Chinese-Dark-AX-editor")
        let exact=app.buttons["精确起止（选填）"];reveal(exact,app,avoidingWheel:true);exact.tap()
        let startLabel=app.staticTexts["开始"];reveal(startLabel,app,avoidingWheel:true)
        screenshot(app,"Investment-Chinese-Dark-AX-exact-start")
        let endLabel=app.staticTexts["结束"];reveal(endLabel,app,avoidingWheel:true)
        screenshot(app,"Investment-Chinese-Dark-AX-exact-end")
        let save=app.buttons["investment-save"];reveal(save,app,avoidingWheel:true);save.tap()
        app.tabBars.buttons["记录"].tap();XCTAssertEqual(body.value as? String,"Synthetic independent Record draft")
        screenshot(app,"Investment-Record-draft-retained")
        app.tabBars.buttons["成长"].tap()
        for _ in 0..<6 {app.swipeDown()}
        let history=app.buttons["investment-history"];reveal(history,app);history.tap()
        screenshot(app,"Investment-Chinese-Dark-AX-review-period")
        let count=app.staticTexts["investment-review-count"];reveal(count,app)
        XCTAssertTrue(count.label.contains("1"),count.label)
        screenshot(app,"Investment-Chinese-Dark-AX-review-summary")
        let day=app.buttons["investment-day-"+originalDay];reveal(day,app);day.tap()
        screenshot(app,"Investment-Chinese-Dark-AX-review-chart-and-day")
        let dayText=day.staticTexts[originalDay]
        let dayDuration=day.staticTexts["0:45:00"]
        XCTAssertTrue(dayText.exists)
        XCTAssertTrue(dayDuration.exists)
        XCTAssertFalse(dayText.frame.intersects(dayDuration.frame),"Daily date and duration must remain separately readable")
        let row=button("investment-session-",app);reveal(row,app);row.tap()
        screenshot(app,"Investment-Chinese-Dark-AX-saved-detail")
    }
    func testRunningColdRelaunchRequiresReviewAndManualDraftStaysOutsideHistory() {
        let app=launch();openHub(app);create(app)
        let start=button("investment-start-",app);reveal(start,app);start.tap()
        XCTAssertTrue(app.buttons["investment-pause"].waitForExistence(timeout:5))
        XCUIDevice.shared.press(.home)
        app.terminate();app.launchArguments.removeAll {$0 == "-PGOSResetData"};app.launch()
        openHub(app)
        let unfinished=app.buttons["investment-unfinished"];reveal(unfinished,app);unfinished.tap()
        XCTAssertTrue(app.staticTexts["investment-timer-state"].label.contains("Recovered time"))
        XCTAssertFalse(app.buttons["investment-pause"].exists)
        screenshot(app,"Investment-English-running-cold-recovery")
        app.buttons["investment-review-save"].tap()
        XCTAssertTrue(app.buttons["investment-save"].waitForExistence(timeout:5))
        let pending=app.buttons["Close and keep pending"];reveal(pending,app);pending.tap()
        XCTAssertTrue(app.buttons["investment-save"].waitForNonExistence(timeout:5))
        let discard=app.buttons["Discard timer"];reveal(discard,app);discard.tap()
        app.sheets.buttons["Discard timer"].tap()
        XCTAssertTrue(discard.waitForNonExistence(timeout:5))
        XCTAssertTrue(app.buttons["investment-history"].waitForExistence(timeout:5))
        let record=button("investment-record-",app);reveal(record,app);record.tap()
        let note=app.textFields["investment-note"];reveal(note,app);note.tap();note.typeText("Synthetic durable manual draft")
        app.buttons["Done"].tap();XCUIDevice.shared.press(.home)
        app.terminate();app.launch()
        openHub(app)
        let draft=app.buttons["Synthetic Reading"];reveal(draft,app);draft.tap()
        XCTAssertEqual(app.textFields["investment-duration"].value as? String,"45")
        let restoredNote=app.textFields["investment-note"];reveal(restoredNote,app)
        XCTAssertEqual(restoredNote.value as? String,"Synthetic durable manual draft")
        let keep=app.buttons["Close and keep draft"];reveal(keep,app);keep.tap()
        let history=app.buttons["investment-history"];reveal(history,app);history.tap()
        XCTAssertTrue(app.staticTexts["No records in this selection"].waitForExistence(timeout:5))
        screenshot(app,"Investment-English-durable-draft-not-counted")
    }

}
