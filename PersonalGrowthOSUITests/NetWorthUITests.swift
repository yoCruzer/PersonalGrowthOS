import XCTest

final class NetWorthUITests: XCTestCase {
    func launch(_ extra: [String] = [], chinese: Bool = false, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PGOSUITesting", "-PGOSResetData", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN":"en_US", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL":"UICTContentSizeCategoryL"] + extra
        app.launch();return app
    }
    func reveal(_ e: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<9 { if e.isHittable { return };app.swipeUp() }
        XCTAssertTrue(e.isHittable,app.debugDescription)
    }
    func open(_ app:XCUIApplication,chinese:Bool=false) {
        app.tabBars.buttons[chinese ? "成长":"Growth"].tap()
        let row=app.buttons["growth-net-worth"];reveal(row,app);row.tap()
        XCTAssertTrue(app.navigationBars[chinese ? "家庭净资产":"Household net worth"].waitForExistence(timeout:8))
    }
    func shot(_ app:XCUIApplication,_ name:String) {
        let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
    func testFirstInventoryAndRepeatedDraftColdLaunch() {
        let app=launch();open(app);shot(app,"V7-empty-native")
        app.buttons["net-worth-record"].tap()
        if app.buttons["Show amounts"].exists { app.buttons["Show amounts"].tap() }
        let add=app.buttons["net-worth-add-item"];reveal(add,app);add.tap()
        let name=app.textFields["net-worth-item-name"];XCTAssertTrue(name.waitForExistence(timeout:4));name.tap();name.typeText("Synthetic household bank")
        let amount=app.textFields["net-worth-initial-amount"];reveal(amount,app);amount.tap();amount.typeText("100000.01")
        app.navigationBars["Balance item"].buttons["Save"].tap()
        let assets=app.switches["Asset scope confirmed"];reveal(assets,app);assets.switches.firstMatch.tap();XCTAssertEqual(assets.value as? String,"1",app.debugDescription)
        let liabilities=app.switches["Liability scope confirmed"];reveal(liabilities,app);liabilities.switches.firstMatch.tap();XCTAssertEqual(liabilities.value as? String,"1",app.debugDescription)
        app.navigationBars["Inventory · CNY"].buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["net-worth-main"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["net-worth-main"].label,"100,000.01")
        shot(app,"V7-single-native")
        let items=app.buttons["Balance items"];reveal(items,app);items.tap()
        let bank=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","Synthetic household bank,")).firstMatch
        XCTAssertTrue(bank.waitForExistence(timeout:5));XCTAssertTrue(bank.label.contains("100,000.01"));bank.tap()
        XCTAssertEqual(app.textFields["net-worth-item-name"].value as? String,"Synthetic household bank")
    }
    func testChineseOverviewHistoryPrivacyAndKeyboard() {
        let app=launch(["-PGOSNetWorthFixture"],chinese:true)
        app.tabBars.buttons["成长"].tap();shot(app,"V1-growth-neighbors")
        open(app,chinese:true);shot(app,"V2-overview-light")
        XCTAssertTrue(app.staticTexts["net-worth-main"].label.contains("1,434,000"))
        app.swipeUp();shot(app,"V2-composition")
        let all=app.buttons["查看全部盘点与金额"];reveal(all,app);all.tap()
        let date=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","2026-10-31")).firstMatch;XCTAssertTrue(date.waitForExistence(timeout:5));date.tap();shot(app,"V9-frozen-history")
        app.navigationBars.buttons.element(boundBy:0).tap();app.navigationBars.buttons.element(boundBy:0).tap()
        for _ in 0..<6 {app.swipeDown()}
        app.buttons["net-worth-privacy"].tap();XCTAssertEqual(app.staticTexts["net-worth-main"].label,"••••");shot(app,"V6-hidden")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","1,434,000")).firstMatch.exists)
        reveal(all,app);all.tap();XCTAssertFalse(app.debugDescription.contains("1,434,000"))
        date.tap();XCTAssertFalse(app.debugDescription.contains("111,000.00"));XCTAssertFalse(app.debugDescription.contains("1,434,000"));shot(app,"V6-hidden-history")
        app.navigationBars.buttons.element(boundBy:0).tap();app.navigationBars.buttons.element(boundBy:0).tap()
        for _ in 0..<6 {app.swipeDown()}
        app.buttons["net-worth-privacy"].tap();app.buttons["net-worth-record"].tap()
        let field=app.textFields["net-worth-amount-0"];reveal(field,app);field.tap();field.typeText("110000.25");shot(app,"V4-repeat-keyboard")
        app.buttons["完成"].tap();app.navigationBars["盘点 · 人民币"].buttons["稍后继续"].tap()
        app.terminate();app.launchArguments.removeAll {$0 == "-PGOSResetData"};app.launch();open(app,chinese:true)
        app.buttons["net-worth-record"].tap();if app.buttons["显示金额"].exists {app.buttons["显示金额"].tap()}
        let restored=app.textFields["net-worth-amount-0"];reveal(restored,app);XCTAssertEqual(restored.value as? String,"110000.25")
    }
    func testChineseLargePartialAndSingleScreens() {
        let app=launch(["-PGOSNetWorthFixture","-PGOSNetWorthSingle","-PGOSNetWorthPartial"],chinese:true,large:true)
        open(app,chinese:true);XCTAssertEqual(app.staticTexts["net-worth-main"].label,"待补全");shot(app,"V5-V8-large-partial")
    }
    func testLargeCompleteAmountAndNegativeLongName() {
        let app=launch(["-PGOSNetWorthFixture","-PGOSNetWorthSingle"],chinese:true,large:true)
        open(app,chinese:true);XCTAssertEqual(app.staticTexts["net-worth-main"].label,"1,390,000.00");shot(app,"V5-large-complete")
        app.terminate()
        let negative=launch(["-PGOSNetWorthFixture","-PGOSNetWorthSingle","-PGOSNetWorthNegative"],chinese:true)
        open(negative,chinese:true);XCTAssertEqual(negative.staticTexts["net-worth-main"].label,"-10,000.00");shot(negative,"V8-negative")
        let items=negative.buttons["余额项目"];reveal(items,negative);items.tap();shot(negative,"V8-long-name")
    }
    func testConfirmationFailurePreservesInputAndRetry() {
        let app=launch(["-PGOSNetWorthFixture","-PGOSNetWorthSingle","-PGOSNetWorthOneItem","-PGOSNetWorthConfirmFailure"],chinese:true)
        open(app,chinese:true);app.buttons["net-worth-record"].tap()
        let field=app.textFields["net-worth-amount-0"];reveal(field,app);field.tap();field.typeText("123456.78");app.buttons["完成"].tap()
        for label in ["已确认本次资产范围","已确认本次负债范围"] {let toggle=app.switches[label];reveal(toggle,app);toggle.switches.firstMatch.tap()}
        app.navigationBars["盘点 · 人民币"].buttons["保存"].tap()
        for _ in 0..<4 {app.swipeDown()}
        XCTAssertTrue(app.staticTexts["net-worth-error"].exists);XCTAssertEqual(field.value as? String,"123456.78");shot(app,"V10-save-failure")
        app.navigationBars["盘点 · 人民币"].buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["net-worth-main"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["net-worth-main"].label,"123,456.78");shot(app,"V10-retry-success")
        app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.995)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)),withVelocity:.slow,thenHoldForDuration:1)
        let background=XCTAttachment(screenshot:XCUIScreen.main.screenshot());background.name="V6-background-system";background.lifetime = .keepAlways;add(background)
        app.activate();XCTAssertEqual(app.staticTexts["net-worth-main"].label,"••••");shot(app,"V6-background-return-hidden")
        XCTAssertFalse(app.debugDescription.contains("123,456.78"))
    }
    func testChineseDarkOverview() {
        let app=launch(["-PGOSNetWorthFixture"],chinese:true);open(app,chinese:true);shot(app,"V3-dark-overview")
        app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.8)).press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)))
        shot(app,"V3-dark-trend-composition")
    }
    func testTrendAndCategoryDrillDownKeepLatestCompositionAndAdjacentModules() {
        let app=launch(["-PGOSNetWorthFixture"],chinese:true)
        app.tabBars.buttons["成长"].tap()
        app.buttons["growth-habits"].tap();shot(app,"V1-habit-neighbor")
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.buttons["growth-weight"].tap();shot(app,"V1-weight-neighbor")
        app.navigationBars.buttons.element(boundBy:0).tap()
        open(app,chinese:true)
        let chart=app.descendants(matching:.any)["net-worth-trend"].firstMatch
        reveal(chart,app)
        app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.8)).press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)))
        shot(app,"V2-trend-scope-break")
        chart.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.45)).tap()
        XCTAssertTrue(app.navigationBars["快照明细"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["2026-10-31"].exists);shot(app,"V9-chart-past-point")
        app.navigationBars["快照明细"].buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["家庭净资产"].waitForExistence(timeout:5))
        app.segmentedControls.buttons["负债"].tap();XCTAssertTrue(app.segmentedControls.buttons["负债"].isSelected);shot(app,"V2-liability-trend")
        let category=app.buttons["net-worth-category-cash"]
        reveal(category,app);category.tap()
        XCTAssertTrue(app.staticTexts["2026-10-31"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["测试银行存款"].exists)
        XCTAssertTrue(app.staticTexts["111,000.00"].exists)
        XCTAssertFalse(app.staticTexts["测试住房估值"].exists);shot(app,"V9-latest-category")
    }
}
