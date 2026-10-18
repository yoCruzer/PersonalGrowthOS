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
        let close=app.buttons["Keep draft"];reveal(close,app);close.tap()
        XCTAssertTrue(app.navigationBars["Record activity"].exists,"Failed keep must not dismiss the editor")
        let error=app.staticTexts["investment-save-error"];reveal(error,app)
        screenshot(app,"External-R2-close-failure-retains-editor")
        reveal(note,app);XCTAssertEqual(note.value as? String,"Synthetic retry draft")
        let retry=app.buttons["Keep draft"];reveal(retry,app);retry.tap()
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
    func testUsageHistoryNaturalWindowMonthPagingAndExactCrossDayFact() {
        let app=launch(extra:["-PGOSInvestmentUsageHistory"]);openHub(app)
        let history=app.buttons["investment-history"];reveal(history,app);history.tap()
        XCTAssertTrue(app.staticTexts["investment-review-total"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["investment-review-total"].label.contains("1:10:00"))
        XCTAssertTrue(app.staticTexts["investment-review-count"].label.contains("51"))
        let toggle=app.switches["Preview selected month"];reveal(toggle,app)
        screenshot(app,"Usage-Investment-before-month-switch")
        toggle.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        XCTAssertEqual(toggle.value as? String,"1",app.debugDescription)
        screenshot(app,"Usage-Investment-after-month-switch")
        let previous=app.buttons["investment-previous-month"];reveal(previous,app)
        let range=app.staticTexts["investment-preview-range"]
        let initial=range.label
        previous.tap()
        XCTAssertNotEqual(range.label,initial)
        screenshot(app,"Usage-Investment-previous-month-full-history")
        app.buttons["investment-next-month"].tap()
        XCTAssertEqual(range.label,initial)
        let next=app.buttons["Next page"];reveal(next,app);next.tap()
        let prior=app.buttons["Previous page"];reveal(prior,app);XCTAssertTrue(prior.isHittable)
        screenshot(app,"Usage-Investment-bounded-second-page")
        for _ in 0..<12 {app.swipeDown()}
        let period=app.segmentedControls["investment-review-period"];XCTAssertTrue(period.isHittable)
        period.buttons["7 days"].tap()
        XCTAssertTrue(app.staticTexts["investment-review-total"].label.contains("0:27:00"))
        XCTAssertTrue(app.staticTexts["investment-review-count"].label.contains("8"))
        let day=button("investment-day-",app);reveal(day,app);day.tap()
        for _ in 0..<6 {app.swipeDown()}
        XCTAssertTrue(app.staticTexts["investment-review-total"].label.contains("0:16:00"))
        XCTAssertTrue(app.staticTexts["investment-review-count"].label.contains("2"))
        let clear=app.buttons["investment-clear-day"];reveal(clear,app);clear.tap()
        XCTAssertTrue(app.staticTexts["investment-review-total"].label.contains("0:27:00"))
        XCTAssertTrue(app.staticTexts["investment-review-count"].label.contains("8"))
        let fact=app.buttons["investment-session-30000001-1111-4222-8333-444444444444"]
        reveal(fact,app);fact.tap()
        XCTAssertTrue(app.staticTexts["Synthetic paused cross-day fact"].waitForExistence(timeout:5))
        let original=app.staticTexts.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","investment-original-day-","0:05:00")).firstMatch
        reveal(original,app);XCTAssertTrue(original.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"identifier BEGINSWITH %@ AND label CONTAINS %@","investment-original-day-","0:15:00")).firstMatch.exists)
        screenshot(app,"Usage-Investment-exact-cross-day-original")
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
        let keep=app.buttons["investment-keep-draft"];reveal(keep,app);keep.tap()
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
        let pending=app.buttons["investment-keep-draft"];reveal(pending,app);pending.tap()
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
        let keep=app.buttons["Keep draft"];reveal(keep,app);keep.tap()
        let history=app.buttons["investment-history"];reveal(history,app);history.tap()
        XCTAssertTrue(app.staticTexts["investment-review-count"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["investment-review-count"].label.contains("0"))
        XCTAssertTrue(app.staticTexts["investment-review-total"].label.contains("0:00:00"))
        let empty=app.staticTexts["No records in this selection"].firstMatch;reveal(empty,app)
        XCTAssertTrue(empty.exists)
        screenshot(app,"Investment-English-durable-draft-not-counted")
    }

}

extension InvestmentUITests {
    func testReviewFixUX1OutsideWindowDateSwitchRetainsDateMonthAndDetailChineseDarkAX() {
        print("PGOS_USAGE_STYLE_DARK");fflush(stdout)
        let app=launch(chinese:true,darkLarge:true,extra:["-PGOSInvestmentReviewFixDates"]);openHub(app,chinese:true)
        let history=app.buttons["investment-history"];reveal(history,app);history.tap()
        let period=app.segmentedControls["investment-review-period"]
        period.buttons["7 天"].tap()
        let date=app.datePickers["investment-inspect-date"];reveal(date,app)
        XCTAssertGreaterThanOrEqual(app.pickerWheels.count,3)
        app.pickerWheels.element(boundBy:0).adjust(toPickerWheelValue:"2026年")
        app.pickerWheels.element(boundBy:1).adjust(toPickerWheelValue:"9月")
        app.pickerWheels.element(boundBy:2).adjust(toPickerWheelValue:"1日")
        let inspect=app.buttons["查看所选日期"];reveal(inspect,app,avoidingWheel:true);inspect.tap()
        for _ in 0..<18 where !period.isHittable {
            app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:0.30)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:0.80)))
        }
        XCTAssertTrue(period.buttons["全部累计"].isSelected)
        let total=app.staticTexts["investment-review-total"];reveal(total,app)
        XCTAssertTrue(total.label.contains("0:45:00"),total.label)
        XCTAssertTrue(app.staticTexts["investment-review-count"].label.contains("1"))
        screenshot(app,"ReviewFix-UX1-Chinese-Dark-maxAX-selected-September1-45min")
        let range=app.staticTexts["investment-preview-range"];reveal(range,app,avoidingWheel:true)
        XCTAssertTrue(range.label.contains("2026-09-01 → 2026-09-30"),range.label)
        let row=app.buttons["investment-session-30000002-1111-4222-8333-444444444444"];reveal(row,app);row.tap()
        let note=app.staticTexts["Synthetic September 1 detail"];reveal(note,app)
        XCTAssertTrue(note.exists)
        screenshot(app,"ReviewFix-UX1-by-ID-detail")
    }
}

extension InvestmentUITests {
    func testReviewFixDuplicateCandidatesShowActualDurationAndClearAfterInputChanges() {
        let app=launch();openHub(app);create(app)
        let record=button("investment-record-",app);reveal(record,app);record.tap()
        let note=app.textFields["investment-note"];reveal(note,app);note.tap();note.typeText("Synthetic matching detail")
        app.buttons["Done"].tap()
        let save=app.buttons["investment-save"];reveal(save,app);save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout:5))
        for _ in 0..<12 where !record.isHittable {app.swipeDown()}
        record.tap();reveal(save,app);save.tap()
        let keep=app.buttons["Keep editing"],confirm=app.buttons["Save anyway"]
        XCTAssertTrue(confirm.waitForExistence(timeout:5))
        if keep.exists {keep.tap()} else {app.coordinate(withNormalizedOffset:CGVector(dx:0.05,dy:0.30)).tap()}
        XCTAssertTrue(confirm.waitForNonExistence(timeout:5))
        let candidate=button("investment-session-",app);reveal(candidate,app)
        XCTAssertTrue(candidate.label.contains("0:45:00"),candidate.label)
        XCTAssertFalse(candidate.label.contains("0:00:00"),candidate.label)
        screenshot(app,"ReviewFix-duplicate-candidate-real-duration")
        candidate.tap()
        let detail=app.staticTexts["Synthetic matching detail"];reveal(detail,app);XCTAssertTrue(detail.exists)
        app.navigationBars.buttons.firstMatch.tap()
        let minutes=app.textFields["investment-duration"]
        for _ in 0..<18 {
            if minutes.exists,minutes.frame.minY >= app.navigationBars["Record activity"].frame.maxY+8,minutes.frame.maxY < app.frame.height*0.75 {break}
            app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:0.35)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:0.55)))
        }
        XCTAssertGreaterThanOrEqual(minutes.frame.minY,app.navigationBars["Record activity"].frame.maxY+8)
        minutes.tap();XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
        minutes.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:2)+"46")
        app.buttons["Done"].tap()
        XCTAssertFalse(candidate.exists,"Time input change invalidates matching IDs without rescanning history")
        reveal(save,app);save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout:5))
    }
}

extension InvestmentUITests {
    private func revealFix2EarlierDuration(_ app: XCUIApplication,chinese: Bool) -> XCUIElement {
        let field=app.textFields["investment-duration"],nav=app.navigationBars[chinese ? "记录活动":"Record activity"]
        for _ in 0..<24 {
            if field.exists,field.frame.minY >= nav.frame.maxY+8,field.frame.maxY <= app.frame.height*0.75 {break}
            let scrollDown = !field.exists || field.frame.minY < nav.frame.maxY+8
            let from=app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:scrollDown ? 0.35:0.65))
            let to=app.coordinate(withNormalizedOffset:CGVector(dx:0.94,dy:scrollDown ? 0.60:0.40))
            from.press(forDuration:0.05,thenDragTo:to)
        }
        XCTAssertTrue(field.exists,app.debugDescription)
        XCTAssertGreaterThanOrEqual(field.frame.minY,nav.frame.maxY+8)
        XCTAssertLessThanOrEqual(field.frame.maxY,app.frame.height*0.75)
        return field
    }
    func testFix2CR05TimerSaveReturnsToHubDefaultAndChineseDarkMaximumText() {
        for chinese in [false,true] {
            print(chinese ? "PGOS_USAGE_STYLE_DARK":"PGOS_USAGE_STYLE_LIGHT");fflush(stdout)
            let app=launch(chinese:chinese,darkLarge:chinese,extra:["-PGOSInvestmentSaveWriteFailure"])
            openHub(app,chinese:chinese);create(app)
            let start=button("investment-start-",app);reveal(start,app);start.tap()
            let finish=app.buttons["investment-finish"];reveal(finish,app);finish.tap()
            let duration=app.textFields["investment-duration"];reveal(duration,app,avoidingWheel:true);duration.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
            duration.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:20)+"3")
            app.buttons[chinese ? "完成":"Done"].tap()
            let note=app.textFields["investment-note"];reveal(note,app,avoidingWheel:true);note.tap();note.typeText("Synthetic timer retained")
            app.buttons[chinese ? "完成":"Done"].tap()
            let save=app.buttons["investment-save"];reveal(save,app,avoidingWheel:true);save.tap()
            let error=app.staticTexts["investment-save-error"];reveal(error,app);XCTAssertTrue(error.exists)
            XCTAssertEqual(note.value as? String,"Synthetic timer retained")
            screenshot(app,"Fix2-CR05-retained-note-before-duration-\(chinese)")
            let retainedDuration=revealFix2EarlierDuration(app,chinese:chinese)
            XCTAssertEqual(retainedDuration.value as? String,"3")
            screenshot(app,"Fix2-CR05-save-failure-retains-input-\(chinese)")
            reveal(save,app,avoidingWheel:true);save.tap()
            screenshot(app,"Fix2-CR05-after-save-landing-\(chinese)")
            XCTAssertTrue(app.navigationBars[chinese ? "计时":"Timer"].waitForNonExistence(timeout:5),"Outer Timer must close after successful confirmation")
            XCTAssertTrue(app.navigationBars[chinese ? "时间投入":"Time investment"].waitForExistence(timeout:5))
            let history=app.buttons["investment-history"];reveal(history,app);XCTAssertTrue(history.isHittable);screenshot(app,"Fix2-CR05-stable-Hub-\(chinese)");history.tap()
            let total=app.staticTexts["investment-review-total"];reveal(total,app)
            XCTAssertTrue(total.label.contains("0:03:00"),total.label)
            XCTAssertTrue(app.staticTexts["investment-review-count"].label.contains("1"))
            let row=button("investment-session-",app);reveal(row,app);XCTAssertEqual(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","investment-session-")).count,1)
            screenshot(app,"Fix2-CR05-one-saved-fact-\(chinese)")
            row.tap();let savedNote=app.staticTexts["Synthetic timer retained"];reveal(savedNote,app);XCTAssertTrue(savedNote.exists)
        }
    }
    func testFix2CR04CandidateEditAndDeleteInvalidateUnchangedDraft() {
        for deleting in [false,true] {
            let chinese=deleting
            print(chinese ? "PGOS_USAGE_STYLE_DARK":"PGOS_USAGE_STYLE_LIGHT");fflush(stdout)
            let app=launch(chinese:chinese,darkLarge:chinese);openHub(app,chinese:chinese);create(app)
            let record=button("investment-record-",app);reveal(record,app);record.tap()
            let note=app.textFields["investment-note"];reveal(note,app,avoidingWheel:true);note.tap();note.typeText("Synthetic formal B")
            app.buttons[chinese ? "完成":"Done"].tap();let save=app.buttons["investment-save"];reveal(save,app,avoidingWheel:true);save.tap()
            XCTAssertTrue(save.waitForNonExistence(timeout:5))
            for _ in 0..<12 where !record.isHittable {app.swipeDown()};record.tap()
            reveal(note,app,avoidingWheel:true);note.tap();note.typeText("Synthetic unchanged draft A");app.buttons[chinese ? "完成":"Done"].tap()
            reveal(save,app,avoidingWheel:true);save.tap();let confirm=app.buttons[chinese ? "仍然保存":"Save anyway"];XCTAssertTrue(confirm.waitForExistence(timeout:5))
            let keep=app.buttons[chinese ? "继续编辑":"Keep editing"]
            if keep.exists {keep.tap()} else {app.coordinate(withNormalizedOffset:CGVector(dx:0.05,dy:0.30)).tap()}
            XCTAssertTrue(confirm.waitForNonExistence(timeout:5))
            let candidate=button("investment-session-",app);reveal(candidate,app);candidate.tap()
            if deleting {
                let delete=app.buttons["investment-delete-session"];reveal(delete,app);delete.tap();app.sheets.buttons[chinese ? "删除记录":"Delete record"].tap()
            } else {
                let edit=app.buttons["investment-edit-session"];reveal(edit,app);edit.tap()
                let minutes=app.textFields["investment-duration"];reveal(minutes,app);minutes.tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
                minutes.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:2)+"46");app.buttons[chinese ? "完成":"Done"].tap()
                reveal(save,app,avoidingWheel:true);save.tap();XCTAssertTrue(app.navigationBars["Time investment detail"].waitForExistence(timeout:5))
                app.navigationBars.buttons.firstMatch.tap()
            }
            XCTAssertTrue(app.navigationBars[chinese ? "记录活动":"Record activity"].waitForExistence(timeout:5))
            XCTAssertFalse(candidate.exists,"Formal B change must remove A's cached candidate page")
            XCTAssertEqual(note.value as? String,"Synthetic unchanged draft A")
            screenshot(app,"Fix2-CR04-retained-note-before-duration-\(deleting ? "delete":"edit")")
            let retainedDuration=revealFix2EarlierDuration(app,chinese:chinese)
            XCTAssertEqual(retainedDuration.value as? String,"45")
            screenshot(app,"Fix2-CR04-unchanged-draft-after-\(deleting ? "delete":"edit")-B")
            reveal(save,app,avoidingWheel:true);save.tap();XCTAssertTrue(save.waitForNonExistence(timeout:5));XCTAssertFalse(confirm.exists)
        }
    }
}
