import XCTest

final class ImportantDayReviewFixUITests: XCTestCase {
    private func launch(deleteTest: Bool = false, chineseLarge: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-PGOSImportantDaysTest", "-PGOSImportantDaysReviewTest", "-AppleLanguages", chineseLarge ? "(zh-Hans)" : "(en)", "-AppleLocale", chineseLarge ? "zh_CN" : "en_US"]
        if deleteTest { app.launchArguments.append("-PGOSImportantDayDeleteTest") }
        if chineseLarge {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch(); return app
    }
    private func openDay(_ title: String, app: XCUIApplication) {
        (app.tabBars.buttons["Growth"].exists ? app.tabBars.buttons["Growth"] : app.tabBars.buttons["成长"]).tap()
        let days = app.buttons["growth-important-days"]; scrollTo(days, app: app); days.tap()
        app.staticTexts[title].firstMatch.tap()
    }
    private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<10 {
            if element.isHittable { return }
            let startY = app.keyboards.firstMatch.exists ? 0.5 : 0.82
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: startY)).press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.25)))
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
        let calendar = app.buttons["important-day-calendar"]
        for _ in 0..<8 {
            if calendar.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.3)).press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.8)))
        }
        XCTAssertTrue(calendar.isHittable)
        calendar.tap(); app.buttons["Gregorian"].tap()
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
    private func selectEditorCalendar(_ name: String, app: XCUIApplication) {
        let control = app.buttons["important-day-calendar"]
        for _ in 0..<8 {
            if control.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.3)).press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.8)))
        }
        XCTAssertTrue(control.isHittable); control.tap(); app.buttons[name].tap()
    }
    private func openReviewDayEditor(_ app: XCUIApplication) {
        let edit = app.buttons["Edit Important Day"]; scrollTo(edit, app: app); edit.tap()
        XCTAssertTrue(app.buttons["important-day-save"].isEnabled)
        XCTAssertFalse(app.buttons["Use the date in the selected calendar"].exists)
    }
    func testUnconfirmedGregorianCalendarRoundTripCanSaveAndReopenWithEditedTitle() {
        let app = launch(); openDay("Review lunar leap", app: app); openReviewDayEditor(app)
        // Establish the exact legal Gregorian 2023-02-01 starting state through the real editor.
        selectEditorCalendar("Gregorian", app: app)
        app.buttons["Use the date in the selected calendar"].tap(); app.buttons["important-day-save"].tap()
        openReviewDayEditor(app)
        let title = app.textFields["important-day-title"]; title.tap(); title.typeText(" R3b")
        let editedTitle = title.value as? String ?? ""
        XCTAssertTrue(editedTitle.contains("R3b")); XCTAssertTrue(editedTitle.contains("Review lunar leap"))
        let savedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        selectEditorCalendar("Chinese lunar · Shanghai", app: app)
        XCTAssertTrue(app.buttons["Use the date in the selected calendar"].exists)
        XCTAssertFalse(app.buttons["important-day-save"].isEnabled)
        let leap = app.switches["Lunar leap month"]; scrollTo(leap, app: app)
        leap.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); XCTAssertEqual(leap.value as? String, "1")
        selectEditorCalendar("Gregorian", app: app)
        XCTAssertFalse(app.buttons["Use the date in the selected calendar"].exists)
        XCTAssertFalse(leap.exists)
        XCTAssertTrue(app.buttons["important-day-save"].isEnabled)
        XCTAssertEqual(title.value as? String, editedTitle)
        app.buttons["important-day-save"].tap()
        app.terminate(); app.launchArguments.removeAll { $0 == "-PGOSResetData" }; app.launch()
        openDay(savedTitle, app: app); openReviewDayEditor(app)
        XCTAssertEqual(app.textFields["important-day-title"].value as? String, savedTitle)
        XCTAssertFalse(app.switches["Lunar leap month"].exists)
        let preview = app.staticTexts["Gregorian date: 2023-02-01"]; scrollTo(preview, app: app); XCTAssertTrue(preview.exists)
        XCTAssertTrue(app.staticTexts["important-day-preview"].label.contains("elapsed"))
        XCTAssertTrue(app.buttons["important-day-save"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "r3b-gregorian-reopened"; shot.lifetime = .keepAlways; add(shot)
        selectEditorCalendar("Chinese lunar · Shanghai", app: app)
        XCTAssertTrue(app.buttons["Use the date in the selected calendar"].exists)
        XCTAssertFalse(app.buttons["important-day-save"].isEnabled)
        scrollTo(leap, app: app); XCTAssertEqual(leap.value as? String, "0")
        app.buttons["Cancel"].firstMatch.tap()
    }
    func testUnconfirmedReverseCalendarRoundTripAndCancelPreserveSavedLunarFacts() {
        let app = launch(); openDay("Review lunar leap", app: app); openReviewDayEditor(app)
        XCTAssertTrue(app.staticTexts["important-day-preview"].label.contains("elapsed"))
        let title = app.textFields["important-day-title"]; title.tap(); title.typeText(" Cancel me")
        selectEditorCalendar("Gregorian", app: app)
        XCTAssertTrue(app.buttons["Use the date in the selected calendar"].exists)
        XCTAssertFalse(app.buttons["important-day-save"].isEnabled)
        selectEditorCalendar("Chinese lunar · Shanghai", app: app)
        XCTAssertFalse(app.buttons["Use the date in the selected calendar"].exists)
        XCTAssertTrue(app.buttons["important-day-save"].isEnabled)
        let leap = app.switches["Lunar leap month"]; scrollTo(leap, app: app); XCTAssertEqual(leap.value as? String, "1")
        app.buttons["Cancel"].firstMatch.tap()
        openReviewDayEditor(app)
        XCTAssertEqual(app.textFields["important-day-title"].value as? String, "Review lunar leap")
        XCTAssertTrue(app.staticTexts["important-day-preview"].label.contains("elapsed"))
        scrollTo(leap, app: app); XCTAssertEqual(leap.value as? String, "1")
        app.buttons["important-day-save"].tap()
        app.terminate(); app.launchArguments.removeAll { $0 == "-PGOSResetData" }; app.launch()
        openDay("Review lunar leap", app: app); openReviewDayEditor(app)
        scrollTo(leap, app: app); XCTAssertEqual(leap.value as? String, "1")
        let original = app.staticTexts["Gregorian date: 2023-03-22"]; scrollTo(original, app: app); XCTAssertTrue(original.exists)
        XCTAssertTrue(app.staticTexts["important-day-preview"].label.contains("elapsed"))
    }
    func testChineseLargeTextConfirmationKeepsSaveAccessibleAndDraftIntact() {
        let app = launch(chineseLarge: true); openDay("Review annual", app: app); enableDefaultPeriod(app)
        let write = app.buttons["important-day-write"]; scrollTo(write, app: app); write.tap()
        let body = app.textViews["capture-body"]; body.tap(); body.typeText("Chinese accessibility draft")
        app.buttons["important-day-test-change-rule"].tap()
        XCTAssertTrue(app.staticTexts["important-day-operation-confirmation"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["important-day-operation-confirmation"].label, "这个日子的日期已改变，草稿已保留。请先确认下方关联，再保存。")
        XCTAssertTrue(app.buttons["capture-save"].isHittable)
        XCTAssertEqual(body.value as? String, "Chinese accessibility draft")
        let confirm = app.buttons["important-day-confirm-operation"]
        for _ in 0..<12 {
            if confirm.isHittable { break }
            let scroll = app.scrollViews["important-day-confirmation-scroll"]
            if scroll.exists {
                let keyboard = app.keyboards.firstMatch
                let visibleBottom = min(scroll.frame.maxY, keyboard.exists ? keyboard.frame.minY : app.frame.maxY)
                let visibleHeight = visibleBottom - scroll.frame.minY
                print("ReviewConfirmScroll frame=\(scroll.frame) visibleHeight=\(visibleHeight) confirm=\(confirm.frame) wheel=\(app.pickerWheels.firstMatch.value ?? "missing")")
                XCTAssertGreaterThan(visibleHeight, 60)
                // Start in the upper half: the keyboard's suggestion bar extends above its AX frame.
                let origin = scroll.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: scroll.frame.width - 5, dy: visibleHeight * 0.5)).press(forDuration: 0.01, thenDragTo: origin.withOffset(CGVector(dx: scroll.frame.width - 5, dy: 20)))
            } else { app.swipeUp() }
        }
        XCTAssertTrue(confirm.isHittable); confirm.tap()
        XCTAssertEqual(body.value as? String, "Chinese accessibility draft")
        XCTAssertTrue(app.staticTexts["important-day-operation-period"].label.contains("2026-10-16"))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "review-fix-zh-AX-confirmation"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["capture-save"].tap()
        XCTAssertTrue(app.buttons["important-day-write"].waitForExistence(timeout: 5))
    }
    func testDeletingTargetPreservesDraftAndExplainsWhySaveCannotProceed() {
        let app = launch(deleteTest: true); openDay("Review annual", app: app)
        app.buttons["important-day-write"].tap()
        let body = app.textViews["capture-body"]; body.tap(); body.typeText("Draft survives target deletion")
        app.buttons["important-day-test-delete"].tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "Draft survives target deletion")
        XCTAssertTrue(app.staticTexts["This day was removed or archived. Your draft was kept. Restore the day before saving."].exists)
        app.buttons["capture-save"].tap()
        XCTAssertEqual(body.value as? String, "Draft survives target deletion")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Day unavailable"].waitForExistence(timeout: 5))
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
