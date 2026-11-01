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
    func testChineseDarkOverview() {
        let app=launch(["-PGOSNetWorthFixture"],chinese:true);open(app,chinese:true);shot(app,"V3-dark-overview")
    }
}
