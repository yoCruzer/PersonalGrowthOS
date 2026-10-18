import XCTest
import Network
import UIKit

final class AppLaunchSmokeTests: XCTestCase {
    func testUsageHabitDailyFourAndTwoFactsExpandAndOpenExactOriginal() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSQuietWinsTest", "-PGOSUsageHabitDaysTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); app.tabBars.buttons["Growth"].tap(); app.buttons["growth-quiet-wins"].tap()
        let card = app.buttons["quiet-wins-card-habit"]
        for _ in 0..<8 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.label.contains("2 · Check-ins: 6"), card.label); card.tap()
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let todayID = formatter.string(from: Date()), yesterdayID = formatter.string(from: Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: Date())!)
        let today = app.buttons["quiet-wins-habit-day-" + todayID], yesterday = app.buttons["quiet-wins-habit-day-" + yesterdayID]
        XCTAssertTrue(today.waitForExistence(timeout: 5)); XCTAssertTrue(today.label.contains("4 check-ins"), today.label)
        XCTAssertTrue(yesterday.label.contains("2 check-ins"), yesterday.label)
        let sources = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quiet-wins-source-habitLog-"))
        today.tap()
        let firstHierarchy = XCTAttachment(string: app.debugDescription); firstHierarchy.name = "Usage-habit-first-day-expanded"; firstHierarchy.lifetime = .keepAlways; add(firstHierarchy)
        let firstShot = XCTAttachment(screenshot: app.screenshot()); firstShot.name = "Usage-habit-first-day-expanded"; firstShot.lifetime = .keepAlways; add(firstShot)
        XCTAssertEqual(sources.count, 4, app.debugDescription)
        let todayIDs = Set(sources.allElementsBoundByIndex.map(\.identifier)); XCTAssertEqual(todayIDs.count, 4)
        today.tap(); yesterday.tap(); XCTAssertEqual(sources.count, 2)
        let yesterdayIDs = Set(sources.allElementsBoundByIndex.map(\.identifier)); XCTAssertEqual(yesterdayIDs.count, 2)
        XCTAssertTrue(todayIDs.isDisjoint(with: yesterdayIDs)); XCTAssertEqual(todayIDs.union(yesterdayIDs).count, 6)
        yesterday.tap(); today.tap()
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "Usage-habit-expanded-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        let expanded = XCTAttachment(screenshot: app.screenshot()); expanded.name = "Usage-habit-expanded-four-plus-two"; expanded.lifetime = .keepAlways; add(expanded)
        sources.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quiet-wins-habit-log-detail"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["quiet-wins-habit-log-day"].label, todayID)
        XCTAssertEqual(app.staticTexts["quiet-wins-habit-log-result"].label, "Synthetic check-in 1")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Usage-habit-exact-original-day-and-result"; shot.lifetime = .keepAlways; add(shot)
    }

    func testUsageChineseDarkMaximumTextBMIAndWeekdayControls() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-PGOSUITesting","-PGOSResetData","-PGOSUsageWeightTest","-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","-AppleInterfaceStyle","Dark","-UIPreferredContentSizeCategoryName",UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        print("PGOS_USAGE_STYLE_DARK");fflush(stdout);Thread.sleep(forTimeInterval:1)
        app.launch();app.buttons["today-weight"].tap()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<18 where !element.isHittable {app.swipeUp()}
            XCTAssertTrue(element.isHittable,app.debugDescription)
        }
        let edit=app.buttons["bmi-edit"];reveal(edit);edit.tap()
        let height=app.textFields["bmi-height-input"];XCTAssertTrue(height.waitForExistence(timeout:5));height.tap();height.typeText("175")
        app.buttons["完成"].tap()
        let save=app.buttons["bmi-save"];reveal(save);save.tap()
        let value=app.staticTexts["bmi-value"];reveal(value);XCTAssertTrue(value.label.contains("24.5"))
        let bmi=XCTAttachment(screenshot:app.screenshot());bmi.name="Usage-Chinese-Dark-maxAX-BMI";bmi.lifetime = .keepAlways;add(bmi)
        app.navigationBars.buttons.firstMatch.tap();app.buttons["today-todo-add"].tap()
        let title=app.descendants(matching:.any)["todo-title"];XCTAssertTrue(title.waitForExistence(timeout:5));title.typeText("合成自选星期的大字待办")
        app.buttons["todo-dismiss-keyboard"].tap()
        let planned=app.switches["todo-planned-toggle"];reveal(planned);planned.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        let frequency=app.buttons["todo-repeat"];reveal(frequency);frequency.tap();
        let selectedWeekdays=app.buttons["自选星期"]
        for _ in 0..<4 where !selectedWeekdays.exists {app.collectionViews.containing(.button,identifier:"每天").firstMatch.swipeUp()}
        selectedWeekdays.tap()
        let sunday=app.buttons["todo-weekday-7"];reveal(sunday);XCTAssertGreaterThanOrEqual(sunday.frame.height,44);sunday.tap()
        let summary=app.staticTexts["todo-repeat-summary"];reveal(summary)
        let weekdays=XCTAttachment(screenshot:app.screenshot());weekdays.name="Usage-Chinese-Dark-maxAX-weekdays";weekdays.lifetime = .keepAlways;add(weekdays)
        XCTAssertTrue(app.buttons["todo-save"].isHittable);app.buttons["取消"].tap()
    }

    func testUsageMixedTodayAndGrowthDefaultAndChineseMaximumText() {
        continueAfterFailure=false
        for large in [false,true] {
            let app=XCUIApplication()
            app.launchArguments=["-PGOSUITesting","-PGOSResetData","-PGOSQuietWinsTest","-PGOSUsageWeightTest","-PGOSImportantDaysTest","-PGOSInvestmentSegmentReview","-AppleLanguages",large ? "(zh-Hans)" : "(en)","-AppleLocale",large ? "zh_CN" : "en_US","-AppleInterfaceStyle",large ? "Dark" : "Light","-UIPreferredContentSizeCategoryName",large ? UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue : UIContentSizeCategory.large.rawValue]
            print(large ? "PGOS_USAGE_STYLE_DARK" : "PGOS_USAGE_STYLE_LIGHT");fflush(stdout);Thread.sleep(forTimeInterval:1)
            app.launch()
            func shot(_ name: String) {let a=XCTAttachment(screenshot:app.screenshot());a.name="Usage-mixed-\(large ? "Chinese-Dark-maxAX" : "English-Light-default")-"+name;a.lifetime = .keepAlways;add(a)}
            app.tabBars.buttons[large ? "成长" : "Growth"].tap()
            let investment=app.buttons["growth-investment"]
            for _ in 0..<12 where !investment.isHittable {app.swipeUp()}
            investment.tap();XCTAssertTrue(app.navigationBars[large ? "时间投入" : "Time investment"].waitForExistence(timeout:5))
            let intro=app.buttons[large ? "知道了" : "Got it"];if intro.exists {intro.tap()}
            let start=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","investment-start-")).firstMatch
            for _ in 0..<12 where !start.isHittable {app.swipeUp()}
            XCTAssertTrue(start.isHittable,app.debugDescription);start.tap()
            let collapse=app.buttons["investment-collapse-timer"];XCTAssertTrue(collapse.waitForExistence(timeout:5));collapse.tap()
            app.navigationBars.buttons.firstMatch.tap()
            for _ in 0..<12 where !app.buttons["growth-goals"].isHittable {app.swipeDown()}
            app.buttons["growth-goals"].tap()
            XCTAssertTrue(app.navigationBars[large ? "目标与标记" : "Goals and Flags"].waitForExistence(timeout:5),app.debugDescription)
            let goal=app.textFields["new-goal-title"];XCTAssertTrue(goal.waitForExistence(timeout:5));goal.tap();goal.typeText("Synthetic active focus\n")
            let addGoal=app.buttons["add-goal"];for _ in 0..<12 where !addGoal.isHittable {app.swipeUp()};addGoal.tap()
            app.navigationBars.buttons.firstMatch.tap()
            for _ in 0..<12 where !app.buttons["growth-habits"].isHittable {app.swipeDown()}
            for id in ["growth-habits","growth-goals","growth-weight","growth-sleep","growth-investment","growth-important-days","growth-quiet-wins"] {
                let row=app.buttons[id]
                for _ in 0..<12 where !row.isHittable {app.swipeUp()}
                XCTAssertTrue(row.isHittable,app.debugDescription);XCTAssertGreaterThanOrEqual(row.frame.height,44);shot(id)
            }
            app.tabBars.buttons[large ? "今天" : "Today"].tap()
            for index in 0..<7 {shot("Today-\(index)");app.swipeUp()}
            XCTAssertTrue(app.buttons["today-weekly-review"].exists)
            let todayGoal=app.buttons["today-goal-synthetic active focus"]
            for _ in 0..<12 where !todayGoal.isHittable {app.swipeDown()}
            XCTAssertTrue(todayGoal.isHittable,app.debugDescription);shot("Today-active-goal")
            let todayInvestment=app.buttons["today-investment"]
            for _ in 0..<12 where !todayInvestment.isHittable {app.swipeDown()}
            XCTAssertTrue(todayInvestment.isHittable,app.debugDescription);shot("Today-running-investment")
            app.terminate()
        }
    }

    func testUsageOpenTodoIntentPreservesRecordDraft() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-PGOSUITesting","-PGOSResetData","-PGOSUsageElapsedTodoTest","-PGOSTodoReminderDeniedTest","-PGOSUsageTodoRouteTest","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();app.tabBars.buttons["Record"].tap()
        let body=app.textViews["capture-body"];XCTAssertTrue(body.waitForExistence(timeout:5));body.tap();body.typeText("Synthetic Record draft survives Todo intent")
        app.buttons["todo-test-open-intent"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic long elapsed reminder"].firstMatch.waitForExistence(timeout:5))
        app.buttons["Done"].tap()
        XCTAssertEqual(body.value as? String,"Synthetic Record draft survives Todo intent")
        app.tabBars.buttons["Today"].tap();app.buttons["today-todo-add"].tap()
        let title=app.descendants(matching:.any)["todo-title"];XCTAssertTrue(title.waitForExistence(timeout:5));title.typeText("Synthetic editor draft survives queued intent")
        if app.buttons["todo-dismiss-keyboard"].exists {app.buttons["todo-dismiss-keyboard"].tap()}
        app.buttons["todo-editor-test-open-intent"].tap()
        XCTAssertTrue(app.navigationBars["Add Todo"].exists)
        XCTAssertEqual(title.value as? String,"Synthetic editor draft survives queued intent")
        app.buttons["Cancel"].tap()
        let pending=app.buttons["todo-pending-route"];XCTAssertTrue(pending.waitForExistence(timeout:5));pending.tap()
        XCTAssertTrue(app.staticTexts["Synthetic long elapsed reminder"].firstMatch.waitForExistence(timeout:5));app.buttons["Done"].tap()
        app.tabBars.buttons["Record"].tap();XCTAssertEqual(body.value as? String,"Synthetic Record draft survives Todo intent")
    }

    func testUsageNativeAlarmAuthorizationScheduleColdLaunchAndConfirmedCancellation() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-PGOSUITesting","-PGOSResetData","-AppleLanguages","(en)","-AppleLocale","en_US"]
        let monitor=addUIInterruptionMonitor(withDescription:"Explicit synthetic AlarmKit authorization") {alert in
            let text=alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator:" ").lowercased()
            guard text.contains("alarm") || text.contains("闹钟") else {return false}
            if alert.buttons["Allow"].exists {alert.buttons["Allow"].tap();return true}
            if alert.buttons["允许"].exists {alert.buttons["允许"].tap();return true}
            return false
        }
        defer {removeUIInterruptionMonitor(monitor)}
        app.launch();app.buttons["today-todo-add"].tap()
        let title=app.descendants(matching:.any)["todo-title"];XCTAssertTrue(title.waitForExistence(timeout:5));title.typeText("Synthetic native alarm lifecycle")
        if app.buttons["todo-dismiss-keyboard"].exists {app.buttons["todo-dismiss-keyboard"].tap()}
        func reveal(_ element: XCUIElement) {
            for _ in 0..<12 where !element.isHittable {app.swipeUp()}
            XCTAssertTrue(element.isHittable,app.debugDescription)
        }
        let reminder=app.switches["todo-reminder-toggle"];reveal(reminder);reminder.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        let method=app.buttons["todo-reminder-method"];reveal(method);method.tap();app.buttons["Alarm reminder"].tap()
        app.buttons["todo-save"].tap()
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout:5) {
            let alert=springboard.alerts.firstMatch
            let description=XCTAttachment(string:alert.debugDescription);description.name="Usage-native-AlarmKit-authorization";description.lifetime = .keepAlways;add(description)
            let text=alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator:" ").lowercased()
            XCTAssertTrue(text.contains("alarm") || text.contains("闹钟"),alert.debugDescription)
            if alert.buttons["Allow"].exists {alert.buttons["Allow"].tap()}
            else if alert.buttons["允许"].exists {alert.buttons["允许"].tap()}
            else {XCTFail(alert.debugDescription)}
        }
        let status=app.staticTexts["todo-saved-reminder-status"]
        XCTAssertTrue(status.waitForExistence(timeout:10),app.debugDescription)
        if status.label == "Alarm reminders are disabled in iOS Settings." {
            XCTAssertTrue(app.buttons["Open iOS Settings"].exists)
            let denial=XCTAttachment(screenshot:app.screenshot());denial.name="Usage-native-AlarmKit-system-denied";denial.lifetime = .keepAlways;add(denial)
            app.buttons["todo-feedback-view-task"].tap()
            XCTAssertTrue(app.staticTexts["Synthetic native alarm lifecycle"].firstMatch.waitForExistence(timeout:5))
            app.buttons["todo-detail-toggle"].tap()
            throw XCTSkip("Real AlarmKit requestAuthorization returned denied without an authorization alert on this disposable simulator, including after fresh app install. Positive native schedule/cancel and delivery remain NOT_RUN; see mobiletimerd denial log.")
        }
        let scheduled=NSPredicate(format:"label == %@","Reminder scheduled on this device")
        expectation(for:scheduled,evaluatedWith:status);waitForExpectations(timeout:20)
        let before=XCTAttachment(screenshot:app.screenshot());before.name="Usage-native-AlarmKit-accepted";before.lifetime = .keepAlways;add(before)
        app.terminate();app.launchArguments.removeAll {$0 == "-PGOSResetData"};app.launch()
        app.buttons["today-todo-hub"].tap();app.buttons["todo-stat-open"].tap()
        let row=app.staticTexts["Synthetic native alarm lifecycle"].firstMatch;reveal(row);row.tap()
        let detailStatus=app.staticTexts["todo-reminder-status"];reveal(detailStatus)
        expectation(for:scheduled,evaluatedWith:detailStatus);waitForExpectations(timeout:15)
        for _ in 0..<8 where !app.buttons["todo-detail-toggle"].isHittable {app.swipeDown()}
        app.buttons["todo-detail-toggle"].tap();reveal(detailStatus)
        expectation(for:NSPredicate(format:"label == %@","No reminder"),evaluatedWith:detailStatus);waitForExpectations(timeout:15)
        let after=XCTAttachment(screenshot:app.screenshot());after.name="Usage-native-AlarmKit-cancellation-confirmed";after.lifetime = .keepAlways;add(after)
    }

    func testUsageLongElapsedReminderOffersFutureResetAndPreservesSeriesDatesAcrossColdLaunch() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-PGOSUITesting","-PGOSResetData","-PGOSUsageElapsedTodoTest","-PGOSTodoReminderDeniedTest","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();app.buttons["today-todo-hub"].tap();app.buttons["todo-stat-open"].tap()
        let row=app.staticTexts["Synthetic long elapsed reminder"].firstMatch
        for _ in 0..<10 where !row.isHittable {app.swipeUp()}
        XCTAssertTrue(row.isHittable,app.debugDescription);row.tap()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<12 where !element.isHittable {app.swipeUp()}
            XCTAssertTrue(element.isHittable,app.debugDescription)
        }
        let status=app.staticTexts["todo-reminder-status"];reveal(status);XCTAssertTrue(status.label.contains("passed"),status.label)
        XCTAssertFalse(app.buttons["Retry Reminder"].exists)
        let reset=app.buttons["todo-reminder-reset"];reveal(reset);reset.tap()
        XCTAssertTrue(app.navigationBars["Set reminder again"].waitForExistence(timeout:5))
        let quick=app.buttons["todo-reminder-ten-minutes"];reveal(quick);quick.tap()
        XCTAssertTrue(quick.waitForNonExistence(timeout:5))
        reveal(status);XCTAssertEqual(status.label,"Notifications are disabled in iOS Settings.")
        XCTAssertTrue(app.buttons["Open iOS Settings"].exists)
        for _ in 0..<6 {app.swipeDown()}
        XCTAssertTrue(app.staticTexts["Planned: 2020-01-01"].exists);XCTAssertTrue(app.staticTexts["Hard deadline: 2020-01-02"].exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Usage-Todo-long-elapsed-reset-preserves-original-dates";shot.lifetime = .keepAlways;add(shot)
        app.terminate();app.launchArguments.removeAll {$0 == "-PGOSResetData" || $0 == "-PGOSUsageElapsedTodoTest"};app.launch();app.buttons["today-todo-hub"].tap();app.buttons["todo-stat-open"].tap()
        for _ in 0..<10 where !row.isHittable {app.swipeUp()};XCTAssertTrue(row.isHittable);row.tap()
        reveal(status);XCTAssertEqual(status.label,"Notifications are disabled in iOS Settings.")
        XCTAssertFalse(app.buttons["Set reminder again"].exists)
    }

    func testUsageSelectedWeekdaysDraftValidationSaveAndCurrentOccurrenceSkip() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-PGOSUITesting","-PGOSResetData","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();app.buttons["today-todo-add"].tap()
        let title=app.descendants(matching:.any)["todo-title"];XCTAssertTrue(title.waitForExistence(timeout:5));title.typeText("Synthetic Tuesday Sunday")
        if app.buttons["todo-dismiss-keyboard"].exists {app.buttons["todo-dismiss-keyboard"].tap()}
        func reveal(_ element: XCUIElement) {
            for _ in 0..<12 where !element.isHittable {app.swipeUp()}
            XCTAssertTrue(element.isHittable,app.debugDescription)
        }
        let planned=app.switches["todo-planned-toggle"];reveal(planned);planned.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        let repeatPicker=app.buttons["todo-repeat"];reveal(repeatPicker);repeatPicker.tap();app.buttons["Selected weekdays"].tap()
        for day in 1...5 {let button=app.buttons["todo-weekday-\(day)"];reveal(button);button.tap()}
        XCTAssertFalse(app.buttons["todo-save"].isEnabled)
        let tuesday=app.buttons["todo-weekday-2"];reveal(tuesday);tuesday.tap()
        let sunday=app.buttons["todo-weekday-7"];reveal(sunday);sunday.tap()
        XCTAssertTrue(app.buttons["todo-save"].isEnabled)
        let summary=app.staticTexts["todo-repeat-summary"];reveal(summary)
        XCTAssertTrue(summary.label.contains("Tuesday") && summary.label.contains("Sunday"),summary.label)
        let next=app.staticTexts["todo-next-occurrence"];reveal(next);XCTAssertTrue(next.label.contains("Next occurrence:"))
        app.buttons["todo-save"].tap()
        let view=app.buttons["todo-feedback-view-task"];XCTAssertTrue(view.waitForExistence(timeout:5));view.tap()
        XCTAssertTrue(app.buttons["todo-skip"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@ AND label CONTAINS %@","Tuesday","Sunday")).firstMatch.exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Usage-Todo-selected-weekdays-source-detail";shot.lifetime = .keepAlways;add(shot)
        app.buttons["todo-skip"].tap()
        XCTAssertTrue(app.buttons["todo-detail-toggle"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Canceled"].exists)
    }

    func testUsageOptionalBMIHeightValidationReferenceColdLaunchAndClear() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-PGOSUITesting","-PGOSResetData","-PGOSUsageWeightTest","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();app.buttons["today-weight"].tap()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<12 where !element.isHittable {app.swipeUp()}
            XCTAssertTrue(element.isHittable,app.debugDescription)
        }
        let edit=app.buttons["bmi-edit"];reveal(edit);edit.tap()
        XCTAssertTrue(app.navigationBars["BMI settings"].waitForExistence(timeout:5),app.debugDescription)
        let height=app.textFields["bmi-height-input"];XCTAssertTrue(height.waitForExistence(timeout:5),app.debugDescription)
        height.tap();height.typeText("0");app.buttons["Done"].tap();app.buttons["bmi-save"].tap()
        XCTAssertTrue(app.staticTexts["bmi-error"].waitForExistence(timeout:5))
        height.tap();height.typeText(XCUIKeyboardKey.delete.rawValue+"175");app.buttons["Done"].tap();app.buttons["bmi-save"].tap()
        let bmi=app.staticTexts["bmi-value"];reveal(bmi);XCTAssertTrue(bmi.label.contains("24.5"))
        XCTAssertEqual(app.staticTexts["bmi-category"].label,"Overweight reference range")
        edit.tap();app.buttons["bmi-reference"].tap();app.buttons["WHO adult reference"].tap();app.buttons["bmi-save"].tap()
        reveal(bmi);XCTAssertEqual(app.staticTexts["bmi-category"].label,"Usual adult reference range")
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Usage-BMI-current-height-WHO-reference";shot.lifetime = .keepAlways;add(shot)
        app.terminate();app.launchArguments.removeAll {$0 == "-PGOSResetData" || $0 == "-PGOSUsageWeightTest"};app.launch();app.buttons["today-weight"].tap()
        XCTAssertEqual(app.staticTexts["weight-latest-value"].label,"75.0 kg")
        reveal(bmi);XCTAssertTrue(bmi.label.contains("24.5"));XCTAssertEqual(app.staticTexts["bmi-category"].label,"Usual adult reference range")
        reveal(edit);edit.tap();app.buttons["bmi-clear"].tap()
        reveal(edit);XCTAssertFalse(app.staticTexts["bmi-value"].exists)
        XCTAssertTrue(app.staticTexts["WHO adult reference"].exists)
    }

    func testUsageWeightDailyMeansRangesAndDateHistoryEditDeleteRefresh() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSUsageWeightTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); app.buttons["today-weight"].tap()
        XCTAssertTrue(app.staticTexts["weight-latest-value"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["weight-latest-value"].label, "75.0 kg")
        func reveal(_ element: XCUIElement) {
            for _ in 0..<12 where !element.isHittable { app.swipeUp() }
            XCTAssertTrue(element.isHittable, app.debugDescription)
        }
        let ranges = app.buttons["weight-review-range"]; reveal(ranges); ranges.tap(); app.buttons["Last 7 days"].tap()
        let weekly = app.switches["weight-average-week"]; reveal(weekly)
        XCTAssertTrue(weekly.label.contains("73.0 kg"), weekly.label)
        XCTAssertTrue(weekly.label.contains("2 recorded days") && weekly.label.contains("3 measurements"), weekly.label)
        let year = app.switches["weight-average-year"]; reveal(year)
        year.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let all = app.buttons["weight-all-records"]; reveal(all); all.tap()
        let yesterday = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let day = app.buttons["weight-history-day-" + formatter.string(from: yesterday)]; reveal(day); day.tap()
        let row = app.buttons.matching(identifier: "weight-record-row").firstMatch; reveal(row)
        XCTAssertTrue(row.label.contains("72.0 kg"), row.label); row.tap()
        let value = app.textFields["weight-editor-value"]; XCTAssertTrue(value.waitForExistence(timeout: 5))
        value.tap(); value.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "73")
        app.buttons["weight-editor-save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.label.contains("73.0 kg"), row.label)
        reveal(row); row.swipeLeft(); app.buttons["Delete"].tap()
        let confirm = app.buttons["Delete Weight Record"]; XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.label.contains("70.0 kg"), row.label)
        app.buttons["weight-history-previous-day"].tap()
        XCTAssertTrue(app.staticTexts["No records in this selection"].waitForExistence(timeout: 5))
        XCTAssertFalse(row.exists)
        app.buttons["weight-history-next-day"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.label.contains("70.0 kg"), row.label)
        app.navigationBars.buttons["Weight"].tap()
        reveal(weekly)
        XCTAssertTrue(weekly.label.contains("72.5 kg"), weekly.label)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Usage-weight-mean-recomputed-after-day-edit-delete"; shot.lifetime = .keepAlways; add(shot)
    }

    func testUsageEditorListCreationManagementAndCancellationPreserveDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSTodoReminderDeniedTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); app.buttons["today-todo-add"].tap()
        let title = app.descendants(matching: .any)["todo-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.typeText("Synthetic complete draft")
        let notes = app.descendants(matching: .any)["todo-notes"]
        notes.tap(); notes.typeText("Keep these notes")
        app.buttons["todo-dismiss-keyboard"].tap()
        app.switches["todo-important"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.switches["todo-planned-toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.switches["todo-reminder-toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        for _ in 0..<4 where !app.buttons["todo-repeat"].isHittable { app.swipeUp() }
        app.buttons["todo-repeat"].tap(); app.buttons["Every Week"].tap()
        func openLists() {
            for _ in 0..<5 where !app.buttons["todo-editor-list"].isHittable { app.swipeDown() }
            app.buttons["todo-editor-list"].tap()
            XCTAssertTrue(app.buttons["todo-editor-new-list"].waitForExistence(timeout: 5))
        }
        openLists(); app.buttons["todo-editor-new-list"].tap()
        XCTAssertTrue(app.textFields["todo-new-list-name"].waitForExistence(timeout: 5))
        app.navigationBars["New List"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["todo-editor-new-list"].waitForExistence(timeout: 5))
        app.buttons["todo-editor-new-list"].tap()
        let name = app.textFields["todo-new-list-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Synthetic list"); app.buttons["todo-new-list-create"].tap()
        let returned = app.navigationBars["Add Todo"].waitForExistence(timeout: 5)
        let returnedShot = XCTAttachment(screenshot: app.screenshot()); returnedShot.name = "Usage-new-list-return-state"; returnedShot.lifetime = .keepAlways; add(returnedShot)
        XCTAssertTrue(returned, app.debugDescription)
        for _ in 0..<5 where !title.exists { app.swipeDown() }
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["todo-editor-list"].label.contains("Synthetic list"))
        XCTAssertEqual(title.value as? String, "Synthetic complete draft"); XCTAssertEqual(notes.value as? String, "Keep these notes")
        openLists(); app.buttons["todo-editor-manage-lists"].tap()
        let rename = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "todo-list-rename-")).firstMatch
        XCTAssertTrue(rename.waitForExistence(timeout: 5)); rename.tap()
        let renamed = app.textFields["todo-list-rename-name"]; XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        renamed.tap(); renamed.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14) + "Renamed")
        app.buttons["todo-list-rename-save"].tap()
        XCTAssertTrue(app.staticTexts["Renamed"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "todo-list-delete-")).firstMatch.tap()
        app.alerts["Delete List?"].buttons["Delete"].tap()
        app.navigationBars["Manage Lists"].buttons["Done"].tap()
        app.navigationBars["List"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Add Todo"].waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<5 where !title.exists { app.swipeDown() }
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["todo-editor-list"].label.contains("Unclassified"))
        XCTAssertEqual(title.value as? String, "Synthetic complete draft"); XCTAssertEqual(notes.value as? String, "Keep these notes")
        XCTAssertEqual(app.switches["todo-important"].value as? String, "1")
        XCTAssertEqual(app.switches["todo-planned-toggle"].value as? String, "1")
        XCTAssertEqual(app.switches["todo-reminder-toggle"].value as? String, "1")
        app.buttons["todo-save"].tap()
        XCTAssertTrue(app.staticTexts["Todo saved"].waitForExistence(timeout: 5))
        app.buttons["todo-feedback-view-task"].tap()
        XCTAssertTrue(app.staticTexts["Keep these notes"].waitForExistence(timeout: 5))
        app.buttons["todo-edit"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5)); XCTAssertEqual(title.value as? String, "Synthetic complete draft")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Usage-list-draft-preserved-and-saved"; shot.lifetime = .keepAlways; add(shot)
    }

    func testStartupDiagnosticCopiesAndSafeRetryPreservesExistingEntry() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSStartupFailureTest",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let diagnostic = app.staticTexts["startup-diagnostic"]
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 10))
        XCTAssertTrue(diagnostic.label.contains("stage=storeOpen"))
        XCTAssertTrue(diagnostic.label.contains("errorCode=134504"))
        XCTAssertFalse(diagnostic.label.contains("PRIVATE-STARTUP-TOKEN"))
        XCTAssertFalse(diagnostic.label.contains("/private/"))
        app.buttons["startup-copy-diagnostic"].tap()
        XCTAssertEqual(app.buttons["startup-copy-diagnostic"].label, "Copied")
        app.buttons["startup-retry"].tap()
        XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 10))
        XCTAssertFalse(diagnostic.exists)
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["Preserved startup retry fixture"].waitForExistence(timeout: 5))
    }

    func testBackupDisclosesPendingExclusionAndCancelKeepsShares() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSPendingInboxTest",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let initial = app.alerts["Some shared content could not be imported"]
        XCTAssertTrue(initial.waitForExistence(timeout: 10))
        initial.buttons["Keep for Later"].tap()
        app.buttons["settings-button"].tap()
        app.buttons["settings-export-button"].tap()
        app.buttons["Export and Share"].tap()
        let warning = app.alerts["Pending shares are not in this backup"]
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        XCTAssertTrue(warning.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "2 shares")).firstMatch.exists)
        warning.buttons["Cancel"].tap()
        let pending = app.buttons["settings-pending-shares"]
        if !pending.isHittable { app.swipeUp() }
        pending.tap()
        XCTAssertTrue(app.buttons["pending-discard-00000000-0000-0000-0000-000000000001"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["pending-discard-00000000-0000-0000-0000-000000000002"].exists)
    }

    func testKilledImportBeforeSaveReclaimsOwnedCopyAndRetriesPending() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSOwnedCopyRecoveryTest", "-PGOSKillAfterCopy",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["copy-durable-before-save"].waitForExistence(timeout: 10))
        // The file worker is blocked before DB save, while the actual app UI remains usable.
        app.tabBars.buttons["Record"].tap()
        XCTAssertTrue(app.tabBars.buttons["Record"].isSelected)
        app.terminate()
        app.launchArguments.removeAll { ["-PGOSResetData", "-PGOSKillAfterCopy"].contains($0) }
        app.launch()
        XCTAssertTrue(app.staticTexts["originals=1;recovery=0;pending=0"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["Interrupted copy fixture"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["originals=1;recovery=0;pending=0"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertEqual(app.staticTexts.matching(identifier: "Interrupted copy fixture").count, 1)
    }

    func testPendingInboxDefersAndConfirmsOnlySelectedDiscard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSPendingInboxTest",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let alert = app.alerts["Some shared content could not be imported"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Keep for Later"].tap()
        app.buttons["settings-button"].tap()
        let pending = app.buttons["settings-pending-shares"]
        if !pending.isHittable { app.swipeUp() }
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        pending.tap()
        XCTAssertTrue(app.staticTexts["Kept for later"].firstMatch.waitForExistence(timeout: 5))
        let first = app.buttons["pending-discard-00000000-0000-0000-0000-000000000001"]
        let second = app.buttons["pending-discard-00000000-0000-0000-0000-000000000002"]
        first.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(first.exists)
        first.tap()
        app.alerts["Remove this pending share?"].buttons["Discard Share"].tap()
        XCTAssertTrue(first.waitForNonExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-PGOSResetData" }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertFalse(alert.exists)
        app.buttons["settings-button"].tap()
        if !pending.isHittable { app.swipeUp() }
        pending.tap()
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertFalse(first.exists)
        XCTAssertTrue(app.staticTexts["Kept for later"].exists)
    }

    func testDamagedInboxSettingsShowRecoveryNoticeAndRemainUsableAfterRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSPendingInboxTest", "-PGOSPendingStateDamageTest",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let alert = app.alerts["Some shared content could not be imported"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "reminder settings were damaged")).firstMatch.exists)
        alert.buttons["Keep for Later"].tap()
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["Intact share after reminder damage"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments.removeAll { $0 == "-PGOSResetData" }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertFalse(alert.exists)
        app.buttons["settings-button"].tap()
        let pending = app.buttons["settings-pending-shares"]
        if !pending.isHittable { app.swipeUp() }
        pending.tap()
        XCTAssertTrue(app.staticTexts["pending-state-recovery-notice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pending-discard-00000000-0000-0000-0000-000000000001"].exists)
        let notice = XCTAttachment(screenshot: app.screenshot())
        notice.name = "Recovered reminder settings with preserved pending shares"
        notice.lifetime = .keepAlways
        add(notice)
        let second = app.buttons["pending-discard-00000000-0000-0000-0000-000000000002"]
        if !second.exists { app.swipeUp() }
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Kept for later"].firstMatch.exists)
    }

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

        XCTAssertTrue(app.tabBars.buttons["Record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Record"].isHittable)
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

        app.tabBars.buttons["Record"].tap()
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
        editor.press(forDuration: 1)
        let selectAll = app.menuItems["Select All"].exists ? app.menuItems["Select All"] : app.buttons["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), app.debugDescription)
        selectAll.tap()
        editor.typeText("A restart-safe memory edited")
        XCTAssertEqual(editor.value as? String, "A restart-safe memory edited", app.debugDescription)
        app.buttons["entry-edit-save"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["A restart-safe memory edited"].waitForExistence(timeout: 10), app.debugDescription)

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

        app.tabBars.buttons["Record"].tap()
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
        let body = app.textViews["capture-body"]
        body.tap()
        body.typeText("Record draft survives tab switch")
        app.tabBars.buttons["Today"].tap()
        app.tabBars.buttons["Record"].tap()
        XCTAssertEqual(body.value as? String, "Record draft survives tab switch")
        app.buttons["capture-save"].tap()
        XCTAssertTrue(app.staticTexts["Record draft survives tab switch"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Record"].tap()
        XCTAssertEqual(body.value as? String, "")
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

        app.tabBars.buttons["Record"].tap()
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

        app.tabBars.buttons["Record"].tap()
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

        app.tabBars.buttons["Record"].tap()
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
        let manageRelationships = app.buttons["entry-manage-relationships"]
        if !manageRelationships.isHittable { app.swipeUp() }
        XCTAssertTrue(manageRelationships.waitForExistence(timeout: 5))
        manageRelationships.tap()
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
        XCTAssertTrue(app.tabBars.buttons["记录"].exists)
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
        XCTAssertTrue(app.tabBars.buttons["Record"].exists)
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

        XCTAssertTrue(app.buttons["today-open-growth"].waitForExistence(timeout: 5))
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

extension AppLaunchSmokeTests {
    func testBuild9DirectWeightFocusAndContinuationSearchRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertFalse(app.buttons["quick-capture-button"].exists)
        app.buttons["today-add-weight"].tap()
        let weight = app.textFields["weight-editor-value"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(weight.value as? String, "Weight (kg)")
        weight.typeText("72.5")
        let keyboard = XCTAttachment(screenshot: app.screenshot())
        keyboard.name = "Build9 Weight keyboard"
        keyboard.lifetime = .keepAlways
        add(keyboard)
        app.buttons["weight-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["today-latest-weight"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Record"].tap()
        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("Original Build9 memory")
        app.buttons["capture-save"].tap()
        app.staticTexts["Original Build9 memory"].firstMatch.tap()
        app.buttons["entry-actions"].tap()
        app.buttons["entry-toggle-pin"].tap()
        app.buttons["entry-add-thought"].tap()
        let thought = app.textViews["follow-up-editor-body"]
        XCTAssertTrue(thought.waitForExistence(timeout: 5))
        thought.tap()
        thought.typeText("A later insight\nSearchable continuation")
        app.buttons["follow-up-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["A later insight\nSearchable continuation"].waitForExistence(timeout: 5))
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "Build9 Follow-up detail"
        detail.lifetime = .keepAlways
        add(detail)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-PGOSResetData" }
        app.launch()
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["Pinned Entries"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Library"].tap()
        app.buttons["library-search-button"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Searchable continuation")
        XCTAssertTrue(app.staticTexts["Matched Follow-up"].waitForExistence(timeout: 5))
        app.staticTexts["Matched Follow-up"].tap()
        XCTAssertTrue(app.staticTexts["A later insight\nSearchable continuation"].waitForExistence(timeout: 5))
    }
}

extension AppLaunchSmokeTests {
    func testBuild9TodayFirstScreenAndPeriodActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()
        func addHabit(_ title: String, period: String? = nil) {
            app.buttons["add-habit"].tap()
            let name = app.textFields["habit-editor-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText(title)
            if let period {
                app.buttons["habit-goal"].tap()
                app.buttons[period].tap()
                let target = app.textFields["habit-daily-target"]
                XCTAssertTrue(target.waitForExistence(timeout: 5))
                target.tap()
                let currentValue = target.value as? String ?? ""
                target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count) + "2")
            }
            app.buttons["habit-editor-save"].tap()
            XCTAssertTrue(name.waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.buttons["add-habit"].isHittable)
        }
        for title in ["Read", "Walk", "Write"] { addHabit(title) }
        app.navigationBars.buttons["Growth"].tap()
        app.buttons["growth-goals"].tap()
        for title in ["Learn something", "Make time outdoors"] {
            let field = app.textFields["new-goal-title"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(title)
            app.buttons["add-goal"].tap()
        }
        app.keyboards.buttons.matching(NSPredicate(format: "identifier ==[c] %@", "return")).firstMatch.tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["today-add-weight"].waitForExistence(timeout: 5))
        for title in ["read", "walk", "write"] {
            XCTAssertTrue(app.buttons["today-habit-\(title)"].isHittable)
        }
        XCTAssertTrue(app.buttons["today-add-weight"].isHittable)
        XCTAssertTrue(app.buttons["today-goal-learn something"].isHittable)
        XCTAssertTrue(app.buttons["today-goal-make time outdoors"].isHittable)
        let first = XCTAttachment(screenshot: app.screenshot())
        first.name = "Build9 Today iPhone16 3 habits 2 goals"
        first.lifetime = .keepAlways
        add(first)
        app.tabBars.buttons["Growth"].tap()
        app.navigationBars.buttons["Growth"].tap()
        app.buttons["growth-habits"].tap()
        addHabit("Weekly reading", period: "Times per Week")
        addHabit("Monthly outdoors", period: "Times per Month")
        app.tabBars.buttons["Today"].tap()
        app.swipeUp()
        let weeklyRow = app.buttons["habit-weekly reading"]
        XCTAssertTrue(weeklyRow.waitForExistence(timeout: 5))
        let periodShot = XCTAttachment(screenshot: app.screenshot())
        periodShot.name = "Build9 Today weekly monthly shared actions"
        periodShot.lifetime = .keepAlways
        add(periodShot)
        let weeklyCell = app.cells.containing(.button, identifier: "habit-weekly reading").firstMatch
        let weeklyAction = weeklyCell.buttons["habit-overview-check-in"]
        XCTAssertTrue(weeklyAction.isHittable)
        weeklyAction.tap()
        XCTAssertFalse(weeklyAction.isEnabled)
        let monthlyCell = app.cells.containing(.button, identifier: "habit-monthly outdoors").firstMatch
        let monthlyAction = monthlyCell.buttons["habit-overview-check-in"]
        if !monthlyAction.isHittable { app.swipeUp() }
        XCTAssertTrue(monthlyAction.isHittable)
        monthlyAction.tap()
        XCTAssertFalse(monthlyAction.isEnabled)

    }
}

extension AppLaunchSmokeTests {
    func testBuild9ChineseThoughtEditingDiscardDeletionAndVersion() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["settings-button"].tap()
        let version = app.buttons["settings-version"]
        for _ in 0..<3 where !version.isHittable { app.swipeUp() }
        XCTAssertTrue(version.isHittable)
        version.tap()
        XCTAssertTrue(app.staticTexts["已复制"].waitForExistence(timeout: 5))
        let settingsShot = XCTAttachment(screenshot: app.screenshot())
        settingsShot.name = "Build9 Chinese actual version copied"
        settingsShot.lifetime = .keepAlways
        add(settingsShot)
        app.navigationBars.buttons["完成"].tap()
        app.tabBars.buttons["记录"].tap()
        let original = "保留原来的想法。" + String(repeating: "今天记下一段经历，未来可以再回来补充。\n", count: 12)
        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText(original)
        app.buttons["capture-save"].tap()
        app.staticTexts.matching(NSPredicate(format: "label == %@", original)).firstMatch.tap()
        let addThought = app.buttons["entry-add-thought"]
        for _ in 0..<5 where !addThought.isHittable { app.swipeUp() }
        XCTAssertTrue(addThought.isHittable)
        addThought.tap()
        let thought = app.textViews["follow-up-editor-body"]
        XCTAssertTrue(thought.waitForExistence(timeout: 5))
        thought.tap()
        thought.typeText("新的认识\n保留变化的过程")
        app.navigationBars.buttons["取消"].tap()
        app.alerts.buttons["follow-up-keep-editing"].firstMatch.tap()
        XCTAssertEqual(thought.value as? String, "新的认识\n保留变化的过程")
        app.buttons["follow-up-editor-save"].tap()
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "follow-up-", "编辑")).firstMatch
        for _ in 0..<8 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        XCTAssertFalse(app.buttons["follow-up-editor-save"].isEnabled)
        thought.tap()
        thought.typeText("\n今天有了进展")
        app.buttons["follow-up-editor-save"].tap()
        for _ in 0..<8 where !app.staticTexts["已编辑"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["已编辑"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Build9 Chinese long entry follow-up edited"
        shot.lifetime = .keepAlways
        add(shot)
        let delete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "follow-up-", "删除")).firstMatch
        for _ in 0..<3 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        app.buttons["删除"].firstMatch.tap()
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5))
        XCTAssertTrue(addThought.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["新的认识\n保留变化的过程\n今天有了进展"].exists)
        app.swipeDown()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", original)).firstMatch.exists)
    }
}

extension AppLaunchSmokeTests {
    /// Run with simctl appearance dark and content_size accessibility-extra-large for visual acceptance.
    func testBuild9ManyHabitsExpandAndScroll() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.tabBars.buttons["成长"].tap()
        app.buttons["growth-habits"].tap()
        for index in 1...9 {
            app.buttons["add-habit"].tap()
            let name = app.textFields["habit-editor-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText("习惯\(index)：留一点时间阅读和整理今天的新认识")
            app.buttons["habit-editor-save"].tap()
            XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        }
        app.tabBars.buttons["今天"].tap()
        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "Build9 system dark accessibility extra large Today"
        top.lifetime = .keepAlways
        add(top)
        let expand = app.buttons["today-expand-habits"]
        for _ in 0..<8 where !expand.isHittable { app.swipeUp() }
        XCTAssertTrue(expand.isHittable)
        expand.tap()
        let last = app.buttons["today-habit-习惯9:留一点时间阅读和整理今天的新认识"]
        for _ in 0..<12 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.isHittable)
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "Build9 expanded ninth habit large text"
        expanded.lifetime = .keepAlways
        add(expanded)
        for _ in 0..<5 where !app.buttons["today-add-weight"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["today-add-weight"].isHittable)
    }
}

extension AppLaunchSmokeTests {
    func testBuild9PinnedPreviewAndAllPinnedList() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        for index in 1...4 {
            app.tabBars.buttons["Record"].tap()
            let body = app.textViews["capture-body"]
            XCTAssertTrue(body.waitForExistence(timeout: 5))
            body.tap()
            body.typeText("Pinned memory \(index)")
            app.buttons["capture-save"].tap()
            let row = app.staticTexts["Pinned memory \(index)"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            app.buttons["entry-actions"].tap()
            app.buttons["entry-toggle-pin"].tap()
            app.navigationBars.buttons["Timeline"].tap()
        }
        let all = app.buttons["View All Pinned"]
        for _ in 0..<3 where !all.isHittable { app.swipeUp() }
        XCTAssertTrue(all.isHittable)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "Build9 three pinned shortcuts and all route"
        preview.lifetime = .keepAlways
        add(preview)
        all.tap()
        XCTAssertTrue(app.navigationBars["Pinned Entries"].waitForExistence(timeout: 5))
        for index in 1...4 { XCTAssertTrue(app.staticTexts["Pinned memory \(index)"].exists) }
        let complete = XCTAttachment(screenshot: app.screenshot())
        complete.name = "Build9 all four pinned entries"
        complete.lifetime = .keepAlways
        add(complete)
    }
}

extension AppLaunchSmokeTests {
    func testPR6SearchRefreshesAfterDeletingMatchedFollowUps() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Record"].tap()
        let original = "A long original memory.\n" + String(repeating: "Keep this original paragraph in its historical place.\n", count: 16)
        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText(original)
        app.buttons["capture-save"].tap()
        app.staticTexts.matching(NSPredicate(format: "label == %@", original)).firstMatch.tap()
        for text in [String(repeating: "Earlier context without the query.\n", count: 14), "Needle alpha", "Needle beta"] {
            let add = app.buttons["entry-add-thought"]
            for _ in 0..<12 where !add.isHittable { app.swipeUp() }
            XCTAssertTrue(add.isHittable)
            add.tap()
            let editor = app.textViews["follow-up-editor-body"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            editor.tap()
            editor.typeText(text)
            app.buttons["follow-up-editor-save"].tap()
            XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        }
        app.tabBars.buttons["Library"].tap()
        app.buttons["library-search-button"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Needle")
        app.keyboards.buttons["Search"].tap()
        for text in ["Needle alpha", "Needle beta"] {
            XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5))
            let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "timeline-entry-", text)).firstMatch
            XCTAssertTrue(result.exists)
            // A long result's snippet can overlap the bottom search toolbar; use its visible row.
            let visible = result.frame.intersection(app.frame.inset(by: UIEdgeInsets(top: 180, left: 0, bottom: 150, right: 0)))
            XCTAssertFalse(visible.isEmpty)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
            let target = app.staticTexts.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", text, "follow-up-")).firstMatch
            XCTAssertTrue(target.waitForExistence(timeout: 5))
            XCTAssertTrue(target.isHittable, "Search must scroll to the matching follow-up")
            let identifier = target.identifier
            let delete = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", identifier, "Delete")).firstMatch
            for _ in 0..<3 where !delete.isHittable { app.swipeUp() }
            XCTAssertFalse(delete.frame.isEmpty)
            delete.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let confirmation = app.sheets.buttons["Delete"].firstMatch
            XCTAssertTrue(confirmation.waitForExistence(timeout: 5), app.debugDescription)
            confirmation.tap()
            XCTAssertTrue(delete.waitForNonExistence(timeout: 5), app.debugDescription)
            let back = app.navigationBars["Entry"].buttons["Search"].firstMatch
            XCTAssertTrue(back.isHittable, app.debugDescription)
            back.tap()
            XCTAssertEqual(search.value as? String, "Needle")
            XCTAssertFalse(app.staticTexts[text].exists)
        }
        XCTAssertFalse(app.staticTexts["Matched Follow-up"].exists)
        XCTAssertTrue(app.staticTexts["No Results for “Needle”"].waitForExistence(timeout: 5))
    }
}

extension AppLaunchSmokeTests {
    func testPR6FilesPreviewCancelAndRestore() {
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Record"].tap()
        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("PR6 synthetic restore memory")
        app.buttons["capture-save"].tap()
        app.tabBars.buttons["Today"].tap()
        app.buttons["settings-button"].tap()
        let export = app.buttons["settings-export-button"]
        for _ in 0..<4 where !export.isHittable { app.swipeUp() }
        export.tap()
        app.buttons["Export and Share"].tap()
        let files = app.cells.matching(NSPredicate(format: "label == %@ OR label == %@", "Save to Files", "保存到“文件”")).firstMatch
        for _ in 0..<4 where !files.isHittable { app.swipeUp() }
        XCTAssertTrue(files.waitForExistence(timeout: 10))
        let exportedName = app.otherElements["LP.CaptionBar.TopCaption"].label
        files.tap()
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 20))
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(filename.waitForNonExistence(timeout: 20))
        app.terminate()
        app.launch() // Resets only the dedicated UITesting database, preserving the Files copy.
        // A real new-install browse must not create the default participant or recommended activities.
        app.tabBars.buttons["Growth"].tap()
        let investment = app.buttons["growth-investment"]
        for _ in 0..<5 where !investment.isHittable { app.swipeUp() }
        investment.tap()
        XCTAssertTrue(app.navigationBars["Time investment"].waitForExistence(timeout:5))
        app.tabBars.buttons["Today"].tap()
        func selectBackup() {
            app.buttons["settings-button"].tap()
            let restore = app.buttons["settings-import-button"]
            for _ in 0..<4 where !restore.isHittable { app.swipeUp() }
            restore.tap()
            let file = app.cells.matching(NSPredicate(format: "label CONTAINS %@", exportedName)).firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 15), app.debugDescription)
            file.tap()
            XCTAssertTrue(app.buttons["Restore Backup"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["1 objects, 0 pins, 0 follow-ups"].exists)
        }
        selectBackup()
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].firstMatch.tap()
        } else {
            app.otherElements["PopoverDismissRegion"].tap()
        }
        XCTAssertTrue(app.buttons["Restore Backup"].waitForNonExistence(timeout: 5))
        app.navigationBars.buttons["Done"].tap()
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["No Entries Yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["PR6 synthetic restore memory"].exists)
        app.tabBars.buttons["Today"].tap()
        selectBackup() // Empty-target preflight must still succeed after cancelling the preview.
        app.buttons["Restore Backup"].tap()
        let completed = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Restore completed:")).firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 15))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "PR6 Files restore completed after preview cancellation"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["OK"].tap()
        app.navigationBars.buttons["Done"].tap()
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["PR6 synthetic restore memory"].waitForExistence(timeout: 5))
    }
}

extension AppLaunchSmokeTests {
    private func waitForFixtureHostReady(_ host: XCUIApplication) {
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: host.buttons["capture-provider-host"])
        waitForExpectations(timeout: 15)
    }

    private func openFixtureExtension(_ host: XCUIApplication, button: String) {
        XCTAssertTrue(host.buttons[button].waitForExistence(timeout: 5), host.debugDescription)
        waitForFixtureHostReady(host)
        host.buttons[button].tap()
        let entry = host.cells.matching(NSPredicate(format: "label == %@", "随心log")).firstMatch
        if !entry.waitForExistence(timeout: 5) {
            let more = host.cells.matching(NSPredicate(format: "label == 'More' OR label == '更多'"))
            if more.firstMatch.exists { more.firstMatch.tap() }
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 10), host.debugDescription)
        entry.tap()
        XCTAssertTrue(host.textViews["share-text"].waitForExistence(timeout: 10), host.debugDescription)
    }

    func testRetryAfterEditingPreservesNoteAndRecoveredTextInEntry() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSCaptureShareTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let host = XCUIApplication(bundleIdentifier: "com.yocruzer.CaptureFixtureHost")
        host.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        host.launch()
        openFixtureExtension(host, button: "capture-provider-retry")
        let editor = host.textViews["share-text"]
        expectation(for: NSPredicate(format: "value == %@", "Public host fixture quote"), evaluatedWith: editor)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(host.buttons["Retry"].exists)
        editor.tap()
        editor.typeText("\nPersonal retry note")
        let edited = editor.value as? String ?? ""
        XCTAssertTrue(edited.contains("Personal retry note"))
        host.buttons["Retry"].tap()
        let expected = edited + "\n\nRecovered second passage"
        expectation(for: NSPredicate(format: "value == %@", expected), evaluatedWith: editor)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(host.buttons["Retry"].exists)
        host.buttons["Save"].doubleTap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertFalse(host.alerts.firstMatch.exists)
        waitForFixtureHostReady(host)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-PGOSResetData" }
        app.launch()
        app.tabBars.buttons["Timeline"].tap()
        let row = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Public host fixture quote")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Public host fixture quote")).count, 1)
        row.tap()
        XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testPartialHostRequiresExplicitReadableContentConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSCaptureShareTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let host = XCUIApplication(bundleIdentifier: "com.yocruzer.CaptureFixtureHost")
        host.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        host.launch()
        openFixtureExtension(host, button: "capture-provider-partial")
        let editor = host.textViews["share-text"]
        expectation(for: NSPredicate(format: "value == %@", "Public host fixture quote"), evaluatedWith: editor)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(host.buttons["Copy Diagnostic Report"].exists)
        host.buttons["Save"].tap()
        let confirmation = host.alerts["Save readable content only?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Cancel"].tap()
        XCTAssertEqual(editor.value as? String, "Public host fixture quote")
        host.buttons["Save"].tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: confirmation.buttons["Save Shown Content"])
        waitForExpectations(timeout: 5)
        confirmation.buttons["Save Shown Content"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        waitForFixtureHostReady(host)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-PGOSResetData" }
        app.launch()
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["Public host fixture quote"].waitForExistence(timeout: 10))
    }

    func testReadyShareCancellationReturnsToSystemPicker() {
        continueAfterFailure = false
        let host = XCUIApplication(bundleIdentifier: "com.yocruzer.CaptureFixtureHost")
        host.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        host.launch()
        openFixtureExtension(host, button: "capture-provider-host")
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: host.buttons["Save"])
        waitForExpectations(timeout: 10)
        host.buttons["Cancel"].tap()
        XCTAssertTrue(host.textViews["share-text"].waitForNonExistence(timeout: 5))
        let entry = host.cells.matching(NSPredicate(format: "label == %@", "随心log")).firstMatch
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: entry)
        waitForExpectations(timeout: 10)
        let pickerShot = XCTAttachment(screenshot: host.screenshot())
        pickerShot.name = "System picker after capture cancellation"
        pickerShot.lifetime = .keepAlways
        add(pickerShot)
        entry.tap()
        XCTAssertTrue(host.textViews["share-text"].waitForExistence(timeout: 10))
    }

    func testStandardComposeCancellationHostControl() {
        continueAfterFailure = false
        let host = XCUIApplication(bundleIdentifier: "com.yocruzer.CaptureFixtureHost")
        host.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        host.launch()
        host.buttons["capture-provider-host"].tap()
        let entry = host.cells.matching(NSPredicate(format: "label == 'Cancel Control App'")).firstMatch
        if !entry.waitForExistence(timeout: 5) {
            let more = host.cells.matching(NSPredicate(format: "label == 'More' OR label == '更多'")).firstMatch
            if more.exists { more.tap() }
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 10), host.debugDescription)
        entry.tap()
        let cancel = host.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == '取消'")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), host.debugDescription)
        cancel.tap()
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: entry)
        waitForExpectations(timeout: 10)
    }

    func testLoadingCancellationAndImmediateReopenRejectOldSession() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSCaptureShareTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let host = XCUIApplication(bundleIdentifier: "com.yocruzer.CaptureFixtureHost")
        host.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        host.launch()
        openFixtureExtension(host, button: "capture-provider-delayed")
        XCTAssertFalse(host.buttons["Save"].isEnabled)
        host.buttons["Cancel"].tap()
        XCTAssertTrue(host.textViews["share-text"].waitForNonExistence(timeout: 5))
        let entry = host.cells.matching(NSPredicate(format: "label == %@", "随心log")).firstMatch
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: entry)
        waitForExpectations(timeout: 10)
        // Cancelling an activity returns to the system picker. Dismiss that picker as a user would.
        host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.60))
            .press(forDuration: 0.1, thenDragTo: host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        waitForFixtureHostReady(host)
        XCTAssertFalse(host.staticTexts["delayed-provider-finished"].exists)
        openFixtureExtension(host, button: "capture-provider-host")
        let editor = host.textViews["share-text"]
        expectation(for: NSPredicate(format: "value == %@", "Public host fixture quote"), evaluatedWith: editor)
        waitForExpectations(timeout: 10)
        host.buttons["Save"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        waitForFixtureHostReady(host)
        XCTAssertTrue(host.staticTexts["delayed-provider-finished"].waitForExistence(timeout: 20))
        app.terminate()
        app.launchArguments.removeAll { $0 == "-PGOSResetData" }
        app.launch()
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["Public host fixture quote"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Cancelled session quote"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Public host fixture quote").count, 1)
    }

    func testPublicMixedProviderHostShowsExtensionAndImports() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSCaptureShareTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let host = XCUIApplication(bundleIdentifier: "com.yocruzer.CaptureFixtureHost")
        host.launch()
        host.buttons["capture-provider-host"].tap()
        let extensionButton = host.cells.matching(NSPredicate(format: "label == %@", "随心log")).firstMatch
        if !extensionButton.waitForExistence(timeout: 5) {
            let more = host.cells.matching(NSPredicate(format: "label == 'More' OR label == '更多'"))
            if more.firstMatch.exists { more.firstMatch.tap() }
        }
        XCTAssertTrue(extensionButton.waitForExistence(timeout: 10), host.debugDescription)
        extensionButton.tap()
        let editor = host.textViews["share-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), host.debugDescription)
        let readable = NSPredicate(format: "value == %@", "Public host fixture quote")
        expectation(for: readable, evaluatedWith: editor)
        waitForExpectations(timeout: 10)
        let save = host.buttons.matching(NSPredicate(format: "label == 'Save' OR label == '保存'")).firstMatch
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertFalse(host.alerts.firstMatch.exists, "All fixture content must be read without a partial-save confirmation")
        app.terminate()
        app.launchArguments.removeAll { $0 == "-PGOSResetData" }
        app.launch()
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["Public host fixture quote"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
    }

    func testExternalCaptureSafariShareAndImport() throws {
        continueAfterFailure = false
        let server = try NWListener(using: .tcp, on: 18763)
        let ready = expectation(description: "Synthetic page server ready")
        server.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        server.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { _, _, _, _ in
                let html = """
                <!doctype html><meta name="viewport" content="width=device-width, initial-scale=1"><title>External Capture Fixture</title><meta property="og:site_name" content="Capture Test"><h1>External Capture Fixture</h1><p id="quote">A selected thought with its original source.</p><script>var r=document.createRange();r.selectNodeContents(document.getElementById('quote'));var s=window.getSelection();s.removeAllRanges();s.addRange(r);</script>
                """
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n" + html
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        server.start(queue: .global())
        defer { server.cancel() }
        wait(for: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSCaptureShareTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Library"].tap()
        app.buttons["library-search-button"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("127.0.0.1")
        // iOS 27 may expose the keyboard's Search AX button outside the viewport.
        // Submit the unchanged query through the already-focused native search field.
        search.typeText("\n")
        XCTAssertFalse(app.staticTexts["External Capture Fixture"].exists)
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.terminate()
        safari.launch()
        func dismissKeyboardIntroductionIfPresent() {
            let introduction = safari.otherElements["UIContinuousPathIntroductionView"]
            if introduction.waitForExistence(timeout: 1) {
                let next = introduction.buttons.matching(NSPredicate(format: "label == 'Continue' OR label == '继续'")).firstMatch
                XCTAssertTrue(next.waitForExistence(timeout: 3), safari.debugDescription)
                next.tap()
            }
        }
        dismissKeyboardIntroductionIfPresent()
        // A new synthetic simulator can restore Safari directly into URL editing.
        if !safari.textFields["URL"].isHittable {
            let address = safari.textFields["TabBarItemTitle"]
            XCTAssertTrue(address.waitForExistence(timeout: 10), safari.debugDescription)
            XCTAssertFalse(address.frame.isEmpty)
            XCTAssertTrue(safari.frame.contains(address.frame))
            address.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        dismissKeyboardIntroductionIfPresent()
        XCTAssertTrue(safari.keyboards.firstMatch.waitForExistence(timeout: 5), safari.debugDescription)
        let urlTree = XCTAttachment(string: safari.debugDescription)
        urlTree.name = "Safari URL editing hierarchy"; urlTree.lifetime = .keepAlways; add(urlTree)
        let urlShot = XCTAttachment(screenshot: safari.screenshot())
        urlShot.name = "Safari URL editor"; urlShot.lifetime = .keepAlways; add(urlShot)
        let addressInput = safari.textFields["URL"]
        XCTAssertTrue(addressInput.waitForExistence(timeout: 5), safari.debugDescription)
        XCTAssertTrue(addressInput.isHittable, safari.debugDescription)
        let clear = safari.buttons["ClearTextButton"]
        if clear.exists && clear.isEnabled { clear.tap() }
        // Safari's capsule loses focus during XCTest typing on iOS 27; enter the fixture by normal Paste.
        UIPasteboard.general.string = "http://127.0.0.1:18763/capture.html"
        addressInput.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1)
        let paste = safari.menuItems.matching(NSPredicate(format: "label == 'Paste' OR label == '粘贴'")).firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5), safari.debugDescription)
        paste.tap()
        let allowPaste = safari.alerts.buttons.matching(NSPredicate(format: "label == 'Allow Paste' OR label == '允许粘贴'")).firstMatch
        if allowPaste.waitForExistence(timeout: 1) { allowPaste.tap() }
        XCTAssertEqual(addressInput.value as? String, "http://127.0.0.1:18763/capture.html")
        let go = safari.keyboards.buttons["Go"]
        XCTAssertTrue(go.isEnabled, safari.debugDescription)
        // Prefer the visible native Go control; retain Return for runtimes with an offscreen AX frame.
        if go.isHittable && !go.frame.isEmpty && safari.frame.contains(go.frame) { go.tap() }
        else { addressInput.typeText("\n") }
        XCTAssertTrue(safari.staticTexts["External Capture Fixture"].firstMatch.waitForExistence(timeout: 10), safari.debugDescription)
        let moreMenu = safari.buttons["MoreMenuButton"]
        XCTAssertTrue(moreMenu.waitForExistence(timeout: 5))
        XCTAssertFalse(moreMenu.frame.isEmpty)
        XCTAssertTrue(safari.frame.contains(moreMenu.frame))
        // Selected web text can give this visible Safari button an invalid AX hit point.
        moreMenu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let share = safari.buttons["ShareButton"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), safari.debugDescription)
        share.tap()
        let extensionButton = safari.cells.matching(NSPredicate(format: "label == %@", "随心log")).firstMatch
        if !extensionButton.waitForExistence(timeout: 5) {
            let more = safari.cells.matching(NSPredicate(format: "label == 'More' OR label == '更多'"))
            if more.firstMatch.exists { more.firstMatch.tap() }
        }
        XCTAssertTrue(extensionButton.waitForExistence(timeout: 10), safari.debugDescription)
        extensionButton.tap()
        let editor = safari.textViews["share-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), safari.debugDescription)
        XCTAssertTrue(safari.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "External Capture Fixture")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "A selected thought with its original source.")
        safari.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == '取消'")).firstMatch.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: extensionButton)
        waitForExpectations(timeout: 10)
        let pickerShot = XCTAttachment(screenshot: safari.screenshot())
        pickerShot.name = "Safari system picker after cancellation"
        pickerShot.lifetime = .keepAlways
        add(pickerShot)
        extensionButton.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "A selected thought with its original source.")
        let shot = XCTAttachment(screenshot: safari.screenshot()); shot.name = "External Capture Safari extension"; shot.lifetime = .keepAlways; add(shot)
        let save = safari.buttons.matching(NSPredicate(format: "label == 'Save' OR label == '保存'")).firstMatch
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        app.activate()
        XCTAssertEqual(search.value as? String, "127.0.0.1")
        let title = app.staticTexts["External Capture Fixture"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        title.tap()
        XCTAssertTrue(app.staticTexts["A selected thought with its original source."].exists)
        let sourceLink = app.descendants(matching: .any)["entry-source-link"]
        XCTAssertTrue(sourceLink.waitForExistence(timeout: 5))
        sourceLink.tap()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(safari.staticTexts["External Capture Fixture"].firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments.removeAll { $0 == "-PGOSResetData" }
        app.launch()
        app.tabBars.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["External Capture Fixture"].firstMatch.waitForExistence(timeout: 10))
    }
}

extension AppLaunchSmokeTests {
    func testTodoQuickContinuousInputCompletionStatisticsSearchAndRestart() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["today-todo-add"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        app.buttons["today-todo-add"].tap()
        let title = app.descendants(matching: .any)["todo-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        title.typeText("Buy batteries")
        app.buttons["todo-save-another"].tap()
        XCTAssertTrue(app.staticTexts["todo-saved-another"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["todo-saved-another"].isHittable)
        let saved = XCTAttachment(screenshot: app.screenshot()); saved.name = "Continuous Todo saved feedback remains visible above keyboard"; saved.lifetime = .keepAlways; add(saved)
        title.typeText("Call home")
        app.buttons["todo-save"].tap()
        app.buttons["today-todo-hub"].tap()
        XCTAssertEqual(app.buttons["todo-stat-open"].value as? String, "2")
        app.buttons["todo-stat-open"].tap()
        XCTAssertTrue(app.staticTexts["Buy batteries"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Call home"].exists)
        app.staticTexts["Buy batteries"].tap()
        app.buttons["todo-detail-toggle"].tap()
        XCTAssertTrue(app.staticTexts["Todo completed"].waitForExistence(timeout: 5))
        app.buttons["todo-detail-toggle"].tap()
        XCTAssertTrue(app.staticTexts["Todo reopened"].waitForExistence(timeout: 5))
        app.buttons["todo-cancel"].tap()
        XCTAssertTrue(app.staticTexts["Todo canceled"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments.removeAll { $0 == "-PGOSResetData" }
        app.launch()
        app.tabBars.buttons["Library"].tap()
        app.buttons["library-search-button"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("batteries")
        XCTAssertTrue(app.staticTexts["Buy batteries"].waitForExistence(timeout: 5))
        app.staticTexts["Buy batteries"].tap()
        XCTAssertTrue(app.staticTexts["Canceled"].waitForExistence(timeout: 5))
    }

    func testTodoEntrySourceKeepsOriginalRecord() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Record"].tap()
        let body = app.textViews["capture-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5)); body.tap(); body.typeText("Original entry for action")
        app.buttons["capture-save"].tap()
        XCTAssertTrue(app.staticTexts["Original entry for action"].waitForExistence(timeout: 5))
        app.staticTexts["Original entry for action"].tap()
        app.buttons["entry-actions"].tap()
        app.buttons["entry-create-todo"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["todo-title"].waitForExistence(timeout: 5))
        app.buttons["todo-save"].tap()
        XCTAssertTrue(app.staticTexts["Original entry for action"].exists)
        app.tabBars.buttons["Today"].tap()
        app.buttons["today-todo-hub"].tap()
        app.buttons["todo-stat-open"].tap()
        app.staticTexts["Original entry for action"].tap()
        let source = app.buttons["todo-source-entry"]
        if !source.isHittable { app.swipeUp() }
        XCTAssertTrue(source.waitForExistence(timeout: 5)); source.tap()
        XCTAssertTrue(app.staticTexts["Original entry for action"].waitForExistence(timeout: 5))
    }

    func testAboutContainsRealCommitAndCopiesFullSHAIntoTodoInput() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["settings-button"].tap()
        let commit = app.buttons["settings-commit"]
        for _ in 0..<6 where !commit.isHittable { app.swipeUp() }
        XCTAssertTrue(commit.waitForExistence(timeout: 5))
        let full = commit.value as? String ?? ""
        XCTAssertEqual(full.count, 40)
        XCTAssertTrue(full.allSatisfy { $0.isHexDigit })
        let tag = app.staticTexts["Release Tag"]
        if tag.exists && !tag.isHittable { app.swipeUp() }
        let about = XCTAttachment(screenshot: app.screenshot())
        about.name = "About actual bundle provenance"; about.lifetime = .keepAlways; add(about)
        commit.tap()
        app.buttons["Done"].tap()
        app.buttons["today-todo-add"].tap()
        let title = app.descendants(matching: .any)["todo-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.press(forDuration: 1)
        let paste = app.menuItems["Paste"].exists ? app.menuItems["Paste"] : app.buttons["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5)); paste.tap()
        let allow = app.alerts.buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 1) { allow.tap() }
        XCTAssertEqual(title.value as? String, full)
    }

    func testTodoListCreateRenameFilterAndConfirmedDeleteKeepsTask() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["today-todo-hub"].tap()
        app.buttons["todo-list-filter"].tap(); app.buttons["Manage Lists"].tap()
        let name = app.textFields["todo-list-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Work")
        app.buttons["todo-list-create"].tap()
        XCTAssertTrue(app.staticTexts["Work"].exists)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "todo-list-rename-")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Rename List"].waitForExistence(timeout: 5))
        let renameField = app.textFields["todo-list-rename-name"]
        renameField.tap(); renameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "Home")
        app.buttons["todo-list-rename-save"].tap()
        XCTAssertTrue(app.staticTexts["Home"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["todo-add"].tap()
        let title = app.descendants(matching: .any)["todo-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.typeText("Buy batteries for home")
        app.buttons["todo-dismiss-keyboard"].tap()
        app.buttons["todo-editor-list"].tap(); app.buttons["Home"].tap()
        app.buttons["todo-save"].tap()
        app.buttons["todo-stat-open"].tap()
        app.buttons["todo-list-filter"].tap(); app.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["Buy batteries for home"].waitForExistence(timeout: 5))
        app.buttons["todo-list-filter"].tap(); app.buttons["Manage Lists"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "todo-list-delete-")).firstMatch.tap()
        let deletion = app.alerts["Delete List?"]
        XCTAssertTrue(deletion.waitForExistence(timeout: 5)); deletion.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Home"].exists)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "todo-list-delete-")).firstMatch.tap()
        app.alerts["Delete List?"].buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts["Home"].exists)
        app.buttons["Done"].tap()
        app.buttons["todo-list-filter"].tap(); app.buttons["Unclassified"].tap()
        XCTAssertTrue(app.staticTexts["Buy batteries for home"].waitForExistence(timeout: 5))
        app.staticTexts["Buy batteries for home"].tap()
        app.buttons["todo-detail-toggle"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.buttons["todo-stat-today"].value as? String, "1")
        app.buttons["todo-stat-today"].tap()
        XCTAssertTrue(app.staticTexts["Buy batteries for home"].exists)
    }

    func testTodoDailyRepeatCompletionSkipStopAndRestartKeepsOneOpenOccurrence() {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Todo reminder authorization") { alert in
            for label in ["Allow", "允许"] where alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            return false
        }
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["today-todo-add"].tap()
        let title = app.descendants(matching: .any)["todo-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.typeText("Morning medicine")
        app.buttons["todo-dismiss-keyboard"].tap()
        app.switches["todo-planned-toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.datePickers["todo-planned-day"].waitForExistence(timeout: 5))
        app.switches["todo-reminder-toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        for _ in 0..<5 where !app.buttons["todo-repeat"].isHittable { app.swipeUp() }
        app.buttons["todo-repeat"].tap(); app.buttons["Every Day"].tap()
        app.buttons["todo-save"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        app.buttons["today-todo-hub"].tap()
        XCTAssertTrue(app.buttons["todo-stat-open"].waitForExistence(timeout: 5))
        app.buttons["todo-stat-open"].tap()
        XCTAssertEqual(app.buttons["todo-stat-open"].value as? String, "1")
        app.staticTexts["Morning medicine"].tap()
        app.buttons["todo-detail-toggle"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.buttons["todo-stat-open"].value as? String, "1")
        app.staticTexts["Morning medicine"].tap()
        let skip = app.buttons["todo-skip"]
        for _ in 0..<3 where !skip.isHittable { app.swipeUp() }
        XCTAssertTrue(skip.isHittable); skip.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.buttons["todo-stat-open"].value as? String, "1")
        app.staticTexts["Morning medicine"].tap()
        let stop = app.buttons["todo-stop-series"]
        for _ in 0..<3 where !stop.isHittable { app.swipeUp() }
        stop.tap()
        app.alerts["Stop Entire Series?"].buttons["Stop Entire Series"].tap()
        for _ in 0..<3 where !app.buttons["todo-detail-toggle"].isHittable { app.swipeDown() }
        app.buttons["todo-detail-toggle"].tap()
        app.terminate(); app.launchArguments.removeAll { $0 == "-PGOSResetData" }; app.launch()
        app.buttons["today-todo-hub"].tap()
        XCTAssertEqual(app.buttons["todo-stat-open"].value as? String, "0")
        XCTAssertEqual(app.buttons["todo-stat-today"].value as? String, "2")
    }

    func testTodoChineseDarkLargestTextAndAboutPassSemanticAccessibilityAudit() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        app.launch()
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        app.buttons["today-todo-add"].tap()
        let title = app.descendants(matching: .any)["todo-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["todo-save"].isEnabled)
        let text = "买电池 🔋 并检查未来构建来源，这是完整保留的长标题"
        title.typeText(text)
        app.buttons["todo-dismiss-keyboard"].tap()
        XCTAssertGreaterThan(title.frame.height, 150, "Largest accessibility text must actually enlarge the multiline title")
        try performSemanticAccessibilityAudit(app)
        let editor = XCTAttachment(screenshot: app.screenshot()); editor.name = "Todo Chinese dark largest text editor"; editor.lifetime = .keepAlways; add(editor)
        XCTAssertTrue(app.buttons["todo-save"].isHittable)
        app.buttons["todo-save"].tap()
        app.buttons["today-todo-hub"].tap()
        for _ in 0..<6 where !app.buttons["todo-stat-open"].isHittable { app.swipeUp() }
        XCTAssertEqual(app.buttons["todo-stat-open"].value as? String, "1")
        app.buttons["todo-stat-open"].tap()
        for _ in 0..<10 where !app.staticTexts[text].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5))
        try performSemanticAccessibilityAudit(app)
        let hub = XCTAttachment(screenshot: app.screenshot()); hub.name = "Todo Chinese dark largest text hub"; hub.lifetime = .keepAlways; add(hub)
        app.terminate(); app.launchArguments.removeAll { $0 == "-PGOSResetData" }; app.launch()
        app.buttons["settings-button"].tap()
        let commit = app.buttons["settings-commit"]
        for _ in 0..<12 where !commit.isHittable { app.swipeUp() }
        XCTAssertTrue(commit.isHittable)
        XCTAssertEqual((commit.value as? String)?.count, 40)
        commit.tap()
        try performSemanticAccessibilityAudit(app)
        let about = XCTAttachment(screenshot: app.screenshot()); about.name = "About Chinese dark largest text commit"; about.lifetime = .keepAlways; add(about)
    }
}

extension AppLaunchSmokeTests {
    func testTodoDeniedReminderFeedbackSurvivesEditorDismissalAndOffersSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSTodoReminderDeniedTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); app.buttons["today-todo-add"].tap()
        let title = app.descendants(matching: .any)["todo-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.typeText("Saved despite denial")
        app.buttons["todo-dismiss-keyboard"].tap()
        app.switches["todo-reminder-toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["todo-save"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Todo saved"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Notifications are disabled in iOS Settings."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open iOS Settings"].exists)
        app.buttons["todo-reminder-feedback-dismiss"].tap()
        app.buttons["today-todo-hub"].tap(); app.buttons["todo-stat-open"].tap()
        XCTAssertTrue(app.staticTexts["Saved despite denial"].waitForExistence(timeout: 5))
    }

    func testTodoIntegrityFailureRetainsDataAndOffersDiagnosticAndRawExport() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSTodoIntegrityFailureTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["startup-export-retained"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        app.buttons["startup-copy-diagnostic"].tap()
        app.buttons["startup-export-retained"].tap()
        XCTAssertTrue(app.buttons["startup-share-retained"].waitForExistence(timeout: 10))
        for _ in 0..<3 {
            app.buttons["startup-retry"].tap()
            XCTAssertTrue(app.buttons["startup-export-retained"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.tabBars.firstMatch.exists)
        }
        app.terminate(); app.launchArguments.removeAll { $0 == "-PGOSResetData" }; app.launch()
        XCTAssertTrue(app.buttons["startup-export-retained"].waitForExistence(timeout: 10))
        app.buttons["startup-export-retained"].tap()
        XCTAssertTrue(app.buttons["startup-share-retained"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }
}

extension AppLaunchSmokeTests {
    func testExistingOrdinaryTodoConvertsToWeeklyKeepsIdentityAndRestartsWithSuccessor() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); app.buttons["today-todo-add"].tap()
        let title = app.descendants(matching: .any)["todo-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.typeText("Convert existing action")
        app.buttons["todo-save"].tap()
        app.buttons["today-todo-hub"].tap(); app.buttons["todo-stat-open"].tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "todo-row-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); let originalRowID = row.identifier
        app.staticTexts["Convert existing action"].tap(); app.buttons["todo-edit"].tap()
        app.buttons["todo-dismiss-keyboard"].tap()
        for _ in 0..<5 where !app.buttons["todo-repeat"].isHittable { app.swipeUp() }
        app.buttons["todo-repeat"].tap(); app.buttons["Every Week"].tap()
        XCTAssertTrue(app.staticTexts["todo-repeat-needs-day"].waitForExistence(timeout: 5))
        app.buttons["todo-save"].tap()
        XCTAssertTrue(app.staticTexts["todo-editor-error"].waitForExistence(timeout: 5))
        for _ in 0..<5 where !app.switches["todo-planned-toggle"].isHittable { app.swipeDown() }
        app.switches["todo-planned-toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["todo-save"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Repeating occurrence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)[originalRowID].exists)
        app.buttons["todo-detail-toggle"].tap()
        app.terminate(); app.launchArguments.removeAll { $0 == "-PGOSResetData" }; app.launch()
        app.buttons["today-todo-hub"].tap(); app.buttons["todo-stat-open"].tap()
        XCTAssertEqual(app.buttons["todo-stat-open"].value as? String, "1")
        XCTAssertEqual(app.buttons["todo-stat-today"].value as? String, "1")
        XCTAssertTrue(app.staticTexts["Convert existing action"].exists)
        XCTAssertTrue(app.staticTexts["Repeating occurrence"].exists)
        XCTAssertFalse(app.descendants(matching: .any)[originalRowID].exists)
    }
}

extension AppLaunchSmokeTests {
    func testAllTodoStatusFiltersCombineListSearchAndFourStatistics() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSTodoFiltersTest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); app.buttons["today-todo-hub"].tap()
        XCTAssertEqual(app.buttons["todo-stat-today"].value as? String, "1")
        XCTAssertEqual(app.buttons["todo-stat-week"].value as? String, "1")
        XCTAssertEqual(app.buttons["todo-stat-open"].value as? String, "3")
        XCTAssertEqual(app.buttons["todo-stat-overdue"].value as? String, "1")
        app.buttons["todo-filter"].tap(); app.buttons["All Todos"].tap()
        XCTAssertTrue(app.buttons["todo-status-filter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Filter Open"].exists); XCTAssertTrue(app.staticTexts["Undated unclassified"].exists)
        XCTAssertFalse(app.staticTexts["Filter Done"].exists); XCTAssertFalse(app.staticTexts["Filter Canceled"].exists)
        func reveal(_ title: String) {
            for _ in 0..<5 where !app.staticTexts[title].exists { app.swipeUp() }
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        }
        func select(_ state: String) {
            for _ in 0..<5 where !app.buttons["todo-status-filter"].isHittable { app.swipeDown() }
            app.buttons["todo-status-filter"].tap(); app.buttons[state].tap()
        }
        select("All States")
        reveal("Filter Done"); reveal("Filter Canceled")
        select("Completed"); XCTAssertTrue(app.staticTexts["Filter Done"].exists); XCTAssertFalse(app.staticTexts["Filter Open"].exists)
        select("Canceled"); XCTAssertTrue(app.staticTexts["Filter Canceled"].exists); XCTAssertFalse(app.staticTexts["Filter Done"].exists)
        select("All States")
        for _ in 0..<5 where !app.buttons["todo-list-filter"].isHittable { app.swipeDown() }
        app.buttons["todo-list-filter"].tap(); app.buttons["Filter List"].tap()
        XCTAssertFalse(app.staticTexts["Undated unclassified"].exists)
        let search = app.searchFields.firstMatch
        for _ in 0..<3 where !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Filter Done")
        XCTAssertTrue(app.staticTexts["Filter Done"].waitForExistence(timeout: 5)); XCTAssertFalse(app.staticTexts["Filter Open"].exists)
        app.staticTexts["Filter Done"].tap(); app.buttons["todo-detail-toggle"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Filter Done"].exists)
        app.searchFields.firstMatch.buttons["Clear text"].tap()
        app.buttons["Close"].tap()
        for _ in 0..<5 where !app.buttons["todo-list-filter"].isHittable { app.swipeDown() }
        app.buttons["todo-list-filter"].tap(); app.buttons["All Lists"].tap()
        select("Completed"); XCTAssertFalse(app.staticTexts["Filter Done"].exists)
        select("Incomplete"); reveal("Filter Done")
        app.staticTexts["Filter Done"].tap(); app.buttons["todo-detail-toggle"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for (id, title, count) in [("todo-stat-today", "Filter Done", 1), ("todo-stat-week", "Filter Done", 1), ("todo-stat-open", "Filter Open", 3), ("todo-stat-overdue", "Filter Overdue", 1)] {
            for _ in 0..<6 where !app.buttons[id].isHittable || app.buttons[id].frame.minY < app.navigationBars.firstMatch.frame.maxY {
                app.swipeDown()
            }
            XCTAssertEqual(app.buttons[id].value as? String, String(count)); app.buttons[id].tap()
            reveal(title)
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "todo-row-"))
            XCTAssertEqual(rows.count, count)
            XCTAssertFalse(app.buttons["todo-status-filter"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        app.terminate(); app.launchArguments.removeAll { $0 == "-PGOSResetData" }; app.launch()
        app.buttons["today-todo-hub"].tap(); app.buttons["todo-filter"].tap(); app.buttons["All Todos"].tap()
        XCTAssertTrue(app.staticTexts["Filter Open"].exists); XCTAssertFalse(app.staticTexts["Filter Done"].exists)
    }
}

extension AppLaunchSmokeTests {
    func testAllTodoStatusMenuChineseDarkLargestTextIsAccessible() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSTodoFiltersTest", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        app.launch(); XCTAssertEqual(app.tabBars.buttons.count, 5); app.buttons["today-todo-hub"].tap()
        for _ in 0..<12 where !app.buttons["todo-filter"].isHittable { app.swipeUp() }
        app.buttons["todo-filter"].tap(); app.buttons["全部待办"].tap()
        let status = app.buttons["todo-status-filter"]
        for _ in 0..<8 where !status.isHittable { app.swipeUp() }
        XCTAssertTrue(status.isHittable); XCTAssertGreaterThanOrEqual(status.frame.height, 44)
        XCTAssertTrue(status.label.contains("未完成"))
        try performSemanticAccessibilityAudit(app)
        let selected = XCTAttachment(screenshot: app.screenshot()); selected.name = "Chinese dark maximum Todo status selector"; selected.lifetime = .keepAlways; add(selected)
        status.tap()
        for label in ["未完成", "所有状态", "已完成", "已取消"] { XCTAssertTrue(app.buttons[label].exists) }
        let menu = XCTAttachment(screenshot: app.screenshot()); menu.name = "Chinese dark maximum four Todo states"; menu.lifetime = .keepAlways; add(menu)
        app.buttons["所有状态"].tap()
        XCTAssertTrue(status.label.contains("所有状态"))
    }
}

extension AppLaunchSmokeTests {
    func testQuietWinsHabitRankingKeepsSurvivingEvidenceAndDeletionInvalidatesIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSQuietWinsTest", "-PGOSQuietWinsRankingTest",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Growth"].tap(); app.buttons["growth-quiet-wins"].tap()
        let habitCard = app.buttons["quiet-wins-card-habit"]
        XCTAssertTrue(habitCard.waitForExistence(timeout: 10))
        XCTAssertTrue(habitCard.label.contains("Quiet reading")); XCTAssertTrue(habitCard.label.contains("2"))
        habitCard.tap()
        let sources = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quiet-wins-source-habitLog-"))
        let daily = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quiet-wins-habit-day-"))
        XCTAssertEqual(daily.count, 2); daily.element(boundBy: 0).tap(); daily.element(boundBy: 1).tap()
        XCTAssertTrue(sources.firstMatch.waitForExistence(timeout: 10)); XCTAssertEqual(sources.count, 2)
        sources.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quiet-wins-habit-log-detail"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["quiet-wins-open-habit"].tap()
        let decrease = app.buttons["habit-detail-counter-decrease"]
        XCTAssertTrue(decrease.waitForExistence(timeout: 10)); decrease.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Evidence No Longer Available"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(sources.firstMatch.waitForExistence(timeout: 10)); XCTAssertEqual(sources.count, 1)
        XCTAssertTrue(app.staticTexts["Days with check-ins for “Quiet reading”: 1 · Check-ins: 1"].exists)
        XCTAssertFalse(app.staticTexts["Evidence No Longer Available"].exists)
        let yesterday = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        XCTAssertTrue(sources.firstMatch.label.contains(formatter.string(from: yesterday)))
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Ranking changed, yesterday still valid"; image.lifetime = .keepAlways; add(image)
        // Remove the remaining real source through existing Habit deletion controls.
        sources.firstMatch.tap(); app.buttons["quiet-wins-open-habit"].tap(); app.buttons["habit-actions"].tap(); app.buttons["Delete Permanently"].tap()
        app.alerts["Delete this Habit permanently?"].buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Evidence No Longer Available"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(habitCard.waitForExistence(timeout: 10)); XCTAssertTrue(habitCard.label.contains("Quiet walking"))
        habitCard.tap(); XCTAssertEqual(daily.count, 1); daily.firstMatch.tap(); XCTAssertEqual(sources.count, 1)
        XCTAssertTrue(sources.firstMatch.label.contains("Quiet walking"))
    }

    func testQuietWinsOpenPagesRefreshAfterRealBackgroundImportAndRapidRanges() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSQuietWinsTest", "-PGOSQuietWinsIntegrationTest",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); app.tabBars.buttons["Growth"].tap(); app.buttons["growth-quiet-wins"].tap()
        let marker = app.staticTexts["quiet-wins-test-read"]
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        func importAndWaitForNewRead() {
            let before = marker.label
            let trigger = app.buttons["quiet-wins-test-import"]
            XCTAssertTrue(trigger.waitForExistence(timeout: 10)); trigger.tap()
            let committed = NSPredicate(format: "label == %@", "Import committed")
            expectation(for: committed, evaluatedWith: trigger)
            waitForExpectations(timeout: 15)
            let refreshed = NSPredicate { _, _ in marker.exists && marker.label != before }
            expectation(for: refreshed, evaluatedWith: marker)
            waitForExpectations(timeout: 15)
            XCTAssertFalse(app.staticTexts["Unable to Load Evidence"].exists)
        }
        importAndWaitForNewRead()
        let range = app.buttons["quiet-wins-range"]
        // No card wait between selections: later requests must keep the final range.
        for days in ["Last 7 days", "Last 90 days", "Last 30 days", "Last 7 days", "Last 90 days", "Last 30 days"] {
            range.tap(); app.buttons[days].tap()
        }
        let finalRange = NSPredicate { _, _ in marker.exists && marker.label.hasPrefix("30:") }
        expectation(for: finalRange, evaluatedWith: marker); waitForExpectations(timeout: 15)
        XCTAssertTrue(range.label.contains("Last 30 days"))
        let entryCard = app.buttons["quiet-wins-card-entries"]
        for _ in 0..<6 where !entryCard.isHittable { app.swipeUp() }
        entryCard.tap()
        XCTAssertTrue(app.buttons["quiet-wins-source-entry"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "quiet-wins-source-entry").count, 1)
        importAndWaitForNewRead()
        XCTAssertEqual(app.buttons.matching(identifier: "quiet-wins-source-entry").count, 1)
        app.buttons["quiet-wins-source-entry"].tap()
        XCTAssertTrue(app.staticTexts["A real synthetic record for source navigation."].waitForExistence(timeout: 10))
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Original source after background imports"; image.lifetime = .keepAlways; add(image)
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(marker.waitForExistence(timeout: 10)); XCTAssertTrue(marker.label.hasPrefix("30:"))
    }

    func testQuietWinsFiveSourcesRangeAndTodoUndoRefresh() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSQuietWinsTest",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", "Light"]
        app.launch()
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        app.tabBars.buttons["Growth"].tap()
        app.buttons["growth-quiet-wins"].tap()
        let range = app.buttons["quiet-wins-range"]
        XCTAssertTrue(range.waitForExistence(timeout: 10))
        XCTAssertTrue(range.label.contains("Last 30 days"))
        for days in ["Last 7 days", "Last 90 days", "Last 30 days"] {
            range.tap(); app.buttons[days].tap()
            XCTAssertTrue(app.buttons["quiet-wins-card-goal"].waitForExistence(timeout: 10))
            XCTAssertTrue(range.label.contains(days))
        }
        let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = "Quiet Wins English light evidence cards"; screen.lifetime = .keepAlways; add(screen)
        for (kind, sourceKind, destination) in [
            ("goal", "goal", "goal-edit"), ("habit", "habitLog", "quiet-wins-habit-log-detail"),
            ("entries", "entry", "entry-edit"), ("reviews", "review", "weekly-review-view")
        ] {
            let card = app.buttons["quiet-wins-card-\(kind)"]
            for _ in 0..<8 where !card.isHittable { app.swipeUp() }
            XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
            if kind == "habit" {
                let day = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quiet-wins-habit-day-")).firstMatch
                XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
            }
            let source = kind == "habit" ? app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quiet-wins-source-habitLog-")).firstMatch : app.buttons["quiet-wins-source-\(sourceKind)"]
            XCTAssertTrue(source.waitForExistence(timeout: 10)); source.tap()
            XCTAssertTrue(app.descendants(matching: .any)[destination].firstMatch.waitForExistence(timeout: 10))
            if kind == "entries" { XCTAssertTrue(app.staticTexts["A real synthetic record for source navigation."].exists) }
            if kind == "reviews" {
                let remembered = app.descendants(matching: .any)["weekly-review-remembered"]
                for _ in 0..<8 where !remembered.isHittable { app.swipeUp() }
                XCTAssertTrue(remembered.waitForExistence(timeout: 5))
                XCTAssertEqual(remembered.value as? String, "Quiet week evidence")
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        let todoCard = app.buttons["quiet-wins-card-todos"]
        for _ in 0..<8 where !todoCard.isHittable { app.swipeDown() }
        XCTAssertTrue(todoCard.waitForExistence(timeout: 10)); todoCard.tap()
        app.buttons["quiet-wins-source-todo"].tap()
        let toggle = app.buttons["todo-detail-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10)); toggle.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Evidence No Longer Available"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["quiet-wins-card-goal"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["quiet-wins-card-todos"].exists)
        app.terminate(); app.launchArguments.removeAll { $0 == "-PGOSResetData" }; app.launch()
        app.tabBars.buttons["Growth"].tap(); app.buttons["growth-quiet-wins"].tap()
        XCTAssertTrue(app.buttons["quiet-wins-card-goal"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["quiet-wins-card-todos"].exists)
    }

    func testQuietWinsChineseDarkMaximumTextAndEmptyState() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSQuietWinsTest",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        app.launch(); XCTAssertEqual(app.tabBars.buttons.count, 5)
        app.tabBars.buttons["成长"].tap()
        let entry = app.buttons["growth-quiet-wins"]
        for _ in 0..<8 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.staticTexts["这些事情，你确实做到了"].waitForExistence(timeout: 10))
        let goal = app.buttons["quiet-wins-card-goal"]
        for _ in 0..<8 where !goal.isHittable { app.swipeUp() }
        XCTAssertTrue(goal.label.contains("完成了「Quiet goal」"))
        XCTAssertGreaterThan(goal.frame.height, 100)
        app.swipeUp()
        try performSemanticAccessibilityAudit(app)
        let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = "Quiet Wins Chinese dark maximum accessibility text"; screen.lifetime = .keepAlways; add(screen)
        goal.tap(); XCTAssertTrue(app.buttons["quiet-wins-source-goal"].waitForExistence(timeout: 10))
        try performSemanticAccessibilityAudit(app)
        app.terminate(); app.launchArguments.removeAll { $0 == "-PGOSQuietWinsTest" }; app.launch()
        app.tabBars.buttons["成长"].tap()
        for _ in 0..<8 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["quiet-wins-empty"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["quiet-wins-card-goal"].exists)
    }
}

extension AppLaunchSmokeTests {
    /// The runner setup first installs exact d72c016 and seeds its existing public Todo fixture.
    /// This test deliberately never resets data or creates that fixture in the candidate.
    func testQuietWinsOpensExactD72SyntheticStoreWithoutReset() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["today-todo-hub"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        app.buttons["today-todo-hub"].tap()
        XCTAssertEqual(app.buttons["todo-stat-open"].value as? String, "3")
        XCTAssertEqual(app.buttons["todo-stat-today"].value as? String, "1")
        app.tabBars.buttons["Growth"].tap(); app.buttons["growth-quiet-wins"].tap()
        let card = app.buttons["quiet-wins-card-todos"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("Tasks completed: 1"))
        XCTAssertFalse(app.buttons["quiet-wins-card-goal"].exists)
        card.tap()
        let source = app.buttons["quiet-wins-source-todo"]
        XCTAssertTrue(source.waitForExistence(timeout: 10)); XCTAssertTrue(source.label.contains("Filter Done")); source.tap()
        XCTAssertTrue(app.staticTexts["Filter Done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["todo-detail-toggle"].exists)
        app.terminate(); app.launch()
        app.tabBars.buttons["Growth"].tap(); app.buttons["growth-quiet-wins"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 10)); XCTAssertTrue(card.label.contains("Tasks completed: 1"))
    }
}


extension AppLaunchSmokeTests {
    func testReviewFixWeightCutoffAndFiftyRowPaginationAcrossDays() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-PGOSUITesting","-PGOSResetData","-PGOSWeightReviewFixDates","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();app.buttons["today-weight"].tap()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<20 where !element.isHittable {app.swipeUp()}
            XCTAssertTrue(element.isHittable,app.debugDescription)
        }
        let through=app.datePickers["weight-review-through"];reveal(through)
        through.buttons.firstMatch.tap()
        let calendar=XCTAttachment(string:app.debugDescription);calendar.name="ReviewFix-native-cutoff-calendar";calendar.lifetime = .keepAlways;add(calendar)
        let tenth=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","October 10")).firstMatch
        XCTAssertTrue(tenth.waitForExistence(timeout:5),app.debugDescription);tenth.tap()
        app.navigationBars["Weight"].tap()
        let latest=app.staticTexts["weight-latest-value"]
        for _ in 0..<10 where !latest.isHittable {app.swipeDown()}
        XCTAssertTrue(latest.label.contains("70.59"),latest.label)
        let all=app.buttons["weight-all-records"];reveal(all)
        let rows=app.buttons.matching(identifier:"weight-record-row")
        XCTAssertEqual(rows.count,5,app.debugDescription)
        XCTAssertFalse(rows.allElementsBoundByIndex.contains {$0.label.contains("77.0 kg")})
        let cutoff=XCTAttachment(screenshot:app.screenshot());cutoff.name="ReviewFix-Weight-main-cutoff-October10";cutoff.lifetime = .keepAlways;add(cutoff)
        all.tap()
        let first=app.buttons["weight-history-day-2026-10-01"];reveal(first);first.tap()
        let pageCount=app.staticTexts["weight-page-count"];reveal(pageCount)
        expectation(for:NSPredicate(format:"label == %@","50 measurements"),evaluatedWith:pageCount);waitForExpectations(timeout:5)
        let more=app.buttons["Load more"];reveal(more);more.tap()
        for _ in 0..<30 where !pageCount.isHittable {app.swipeDown()}
        expectation(for:NSPredicate(format:"label == %@","60 measurements"),evaluatedWith:pageCount);waitForExpectations(timeout:5)
        for _ in 0..<30 where !app.buttons["weight-history-day-2026-10-17"].isHittable {app.swipeDown()}
        app.buttons["weight-history-day-2026-10-17"].tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout:5));XCTAssertEqual(rows.count,1)
        XCTAssertTrue(rows.firstMatch.label.contains("77.0 kg"))
        first.tap()
        expectation(for:NSPredicate(format:"label == %@","50 measurements"),evaluatedWith:pageCount);waitForExpectations(timeout:5)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="ReviewFix-Weight-return-A-correct-first-page";shot.lifetime = .keepAlways;add(shot)
    }
}
