import XCTest

final class InvestmentUITests: XCTestCase {
    func launch(chinese: Bool = false, darkLarge: Bool = false,extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting","-PGOSResetData","-AppleLanguages",chinese ? "(zh-Hans)" : "(en)","-AppleLocale",chinese ? "zh_CN" : "en_US"]
        app.launchArguments += ["-AppleInterfaceStyle",darkLarge ? "Dark" : "Light",
                                "-UIPreferredContentSizeCategoryName",darkLarge ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchArguments += extra
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
    func testExternalR2FailedCloseKeepsEditorAndRetrySurvivesColdLaunch() {
        let app=launch(extra:["-PGOSInvestmentCloseWriteFailure"]);openHub(app);create(app)
        let record=button("investment-record-",app);reveal(record,app);record.tap()
        let note=app.textFields["investment-note"];reveal(note,app);note.tap();note.typeText("Synthetic retry draft")
        app.buttons["Done"].tap()
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertTrue(app.navigationBars["Record activity"].waitForExistence(timeout:5))
        let nav=app.navigationBars["Record activity"]
        // Pair the same observed sheet grabber region with R3's successful dismissal.
        app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.09)).press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.95)))
        XCTAssertTrue(nav.exists,"Interactive dismissal must not lose a failed draft")
        screenshot(app,"External-R2-background-and-interactive-failure-retained")
        let close=app.buttons["Close and keep draft"];reveal(close,app);close.tap()
        XCTAssertTrue(app.navigationBars["Record activity"].exists,"Failed keep must not dismiss the editor")
        let error=app.staticTexts["investment-save-error"];reveal(error,app)
        screenshot(app,"External-R2-close-failure-retains-editor")
        reveal(note,app);XCTAssertEqual(note.value as? String,"Synthetic retry draft")
        let retry=app.buttons["Close and keep draft"];reveal(retry,app);retry.tap()
        XCTAssertTrue(retry.waitForNonExistence(timeout:5))
        app.terminate();app.launchArguments.removeAll {$0 == "-PGOSResetData"};app.launch();openHub(app)
        let draft=app.buttons["Synthetic Reading"];reveal(draft,app);draft.tap()
        let restored=app.textFields["investment-note"];reveal(restored,app)
        XCTAssertEqual(restored.value as? String,"Synthetic retry draft")
        screenshot(app,"External-R2-draft-reopened-after-success")
    }
    func testExternalR3MultipleSegmentsRequireExplicitContinuousReplacement() {
        let app=launch(extra:["-PGOSInvestmentSegmentReview"]);openHub(app)
        let history=app.buttons["investment-history"];reveal(history,app);history.tap()
        XCTAssertTrue(app.staticTexts["investment-review-total"].label.contains("0:20:00"))
        let row=button("investment-session-",app);reveal(row,app);row.tap()
        let edit=app.buttons["investment-edit-session"];reveal(edit,app);edit.tap()
        let minutes=app.textFields["investment-duration"];XCTAssertEqual(minutes.value as? String,"20")
        let exact=app.buttons["Optional exact interval"];reveal(exact,app);exact.tap()
        let apply=app.buttons["Use this exact interval"];reveal(apply,app);apply.tap()
        screenshot(app,"External-R3-continuous-replacement-request")
        let keep=app.buttons["Keep effective segments"]
        let offered=keep.waitForExistence(timeout:2)
        if offered {keep.tap()}
        reveal(minutes,app)
        XCTAssertEqual(minutes.value as? String,"20","Unconfirmed envelope must not include the pause")
        XCTAssertTrue(offered,"Multiple segments require a separate explicit decision")
        let note=app.textFields["investment-note"];reveal(note,app);note.tap();note.typeText("Synthetic segment note")
        app.buttons["Done"].tap()
        let save=app.buttons["investment-save"];reveal(save,app);save.tap()
        XCTAssertTrue(app.staticTexts["Synthetic segment note"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["0:20:00"].exists)
        app.terminate();app.launchArguments.removeAll {$0 == "-PGOSResetData"};app.launch();openHub(app)
        let restoredHistory=app.buttons["investment-history"];reveal(restoredHistory,app);restoredHistory.tap()
        XCTAssertTrue(app.staticTexts["investment-review-total"].label.contains("0:20:00"))
        let restoredRow=button("investment-session-",app);reveal(restoredRow,app);restoredRow.tap()
        let restoredEdit=app.buttons["investment-edit-session"];reveal(restoredEdit,app);restoredEdit.tap()
        let again=app.buttons["Optional exact interval"];reveal(again,app);again.tap()
        let replaceRequest=app.buttons["Use this exact interval"];reveal(replaceRequest,app);replaceRequest.tap()
        let replace=app.buttons["Replace effective segments"];XCTAssertTrue(replace.waitForExistence(timeout:3))
        screenshot(app,"External-R3-explicit-warning-before-replacement");replace.tap()
        let revised=app.textFields["investment-duration"];reveal(revised,app);XCTAssertEqual(revised.value as? String,"25")
        let revisedSave=app.buttons["investment-save"];reveal(revisedSave,app);revisedSave.tap()
        XCTAssertTrue(app.staticTexts["0:25:00"].waitForExistence(timeout:5))
        app.terminate();app.launch();openHub(app)
        let finalHistory=app.buttons["investment-history"];reveal(finalHistory,app);finalHistory.tap()
        XCTAssertTrue(app.staticTexts["investment-review-total"].label.contains("0:25:00"))
        XCTAssertTrue(app.staticTexts["investment-review-count"].label.contains("1"))
        screenshot(app,"External-R3-explicit-replacement-reopened-statistics")
    }
    func testExternalR3ChineseDarkAXConfirmationPreservesOrExplicitlyReplacesSegments() {
        let app=launch(chinese:true,darkLarge:true,extra:["-PGOSInvestmentSegmentReview"]);openHub(app,chinese:true)
        let history=app.buttons["investment-history"];reveal(history,app);history.tap()
        let row=button("investment-session-",app);reveal(row,app);row.tap()
        let edit=app.buttons["investment-edit-session"];reveal(edit,app);edit.tap()
        let exact=app.buttons["精确起止（选填）"];reveal(exact,app,avoidingWheel:true);exact.tap()
        let warning=app.staticTexts["这条记录含多段有效时间。改为连续区间可能把暂停时间算入投入。"]
        reveal(warning,app,avoidingWheel:true);screenshot(app,"External-R3-Chinese-Dark-AX-original-segment-warning")
        let apply=app.buttons["采用此精确区间"];reveal(apply,app,avoidingWheel:true);apply.tap()
        screenshot(app,"External-R3-Chinese-Dark-AX-confirmation-top")
        let change=app.staticTexts["investment-interval-change"]
        reveal(change,app);XCTAssertEqual(change.label,"0:20:00 \u{2192} 0:25:00")
        screenshot(app,"External-R3-Chinese-Dark-AX-full-warning-and-duration")
        let keep=app.buttons["保留原有效时间段"],replace=app.buttons["确认替换有效时间段"]
        reveal(replace,app);XCTAssertTrue(keep.isHittable);XCTAssertTrue(replace.isHittable)
        screenshot(app,"External-R3-Chinese-Dark-AX-explicit-two-choice-warning");keep.tap()
        let minutes=app.textFields["investment-duration"]
        func revealMinutesAbove() {
            for _ in 0..<12 {
                if minutes.isHittable {break}
                app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:0.30)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:0.80)))
            }
            XCTAssertTrue(minutes.isHittable,app.debugDescription)
        }
        revealMinutesAbove();XCTAssertEqual(minutes.value as? String,"20")
        reveal(apply,app,avoidingWheel:true);apply.tap()
        let confirmationNav=app.navigationBars["精确起止（选填）"]
        XCTAssertTrue(confirmationNav.waitForExistence(timeout:3))
        // The recorded large sheet grabber is at y=79 on this 402x874 fixture.
        app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.09)).press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.95)))
        XCTAssertTrue(confirmationNav.waitForNonExistence(timeout:5))
        revealMinutesAbove();XCTAssertEqual(minutes.value as? String,"20","Interactive cancellation must preserve effective segments")
        reveal(apply,app,avoidingWheel:true);apply.tap();reveal(replace,app);replace.tap()
        revealMinutesAbove();XCTAssertEqual(minutes.value as? String,"25")
        let save=app.buttons["investment-save"];reveal(save,app,avoidingWheel:true);save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout:5))
        app.terminate();app.launchArguments.removeAll {$0 == "-PGOSResetData"};app.launch();openHub(app,chinese:true)
        let restoredHistory=app.buttons["investment-history"];reveal(restoredHistory,app);restoredHistory.tap()
        let total=app.staticTexts["investment-review-total"];reveal(total,app);XCTAssertTrue(total.label.contains("0:25:00"))
        let count=app.staticTexts["investment-review-count"];reveal(count,app);XCTAssertTrue(count.label.contains("1"))
        screenshot(app,"External-R3-Chinese-Dark-AX-confirmed-duration-reopened-statistics")
    }
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
        let detailEdit=app.buttons["investment-edit-session"];reveal(detailEdit,app)
        screenshot(app,"Investment-Chinese-Dark-AX-original-day-contribution")
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
