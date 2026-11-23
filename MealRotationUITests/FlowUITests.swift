import Foundation
import XCTest

final class FlowUITests: XCTestCase {
    enum Language: String, CaseIterable {
        case en, simplified = "zh-Hans", traditional = "zh-Hant"
        var locale: String {
            switch self {
            case .en: "en_US"
            case .simplified: "zh_CN"
            case .traditional: "zh_TW"
            }
        }
        var moreWidget: String {
            switch self {
            case .en: "Home Screen widget"
            case .simplified: "桌面小组件"
            case .traditional: "主畫面小工具"
            }
        }
        var archived: String {
            switch self {
            case .en: "Archived dinners"
            case .simplified: "已归档晚饭"
            case .traditional: "已封存晚餐"
            }
        }
    }

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        executionTimeAllowance = 900
        app = XCUIApplication()
    }

    private func launch(_ args: [String] = [], language: Language = .en,
                        reset: Bool = true, environment: [String: String] = [:]) {
        if app.state != .notRunning { app.terminate() }
        app.launchArguments = ["-ui-testing"] + (reset ? ["-reset"] : []) + [
            "-AppleLanguages", "(\(language.rawValue))", "-AppleLocale", language.locale
        ] + args
        app.launchEnvironment = environment
        app.launch()
    }

    @discardableResult
    private func waitForButton(_ id: String, scroll: Bool = false) -> XCUIElement {
        let query = app.buttons.matching(identifier: id)
        let first = query.firstMatch
        _ = first.waitForExistence(timeout: 10)
        for _ in 0..<6 {
            if let button = query.allElementsBoundByIndex.first(where: \.isHittable) { return button }
            if scroll { app.swipeUp() }
            else { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        }
        XCTAssertTrue(first.exists && first.isHittable, id)
        return first
    }

    private func tap(_ id: String, scroll: Bool = false) {
        waitForButton(id, scroll: scroll).tap()
    }

    private func assertText(_ name: String) {
        XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 10), name)
    }

    private func replace(_ field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let count = (field.value as? String)?.count ?? 0
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count + 2) + value)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func code(_ json: String) -> String {
        "MR1:" + Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func testFirstRunAddsSingleDinnerAndThenBatch() {
        launch(environment: ["UI_DINNER_NAMES": "Chili\n Tacos\n chili \nPasta"])
        tap("tonight.add")
        let field = app.textViews["add.names"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("Soup")
        tap("add.save")
        XCTAssertEqual(waitForButton("tonight.log.0").label, "Log Soup")
        XCTAssertFalse(app.buttons["tonight.shuffle"].exists)
        tap("tonight.add")
        tap("add.insert_test_text")
        tap("add.save")
        XCTAssertEqual(waitForButton("tonight.log.0").label, "Log Chili")
        XCTAssertTrue(app.buttons["tonight.shuffle"].exists)
    }

    func testLogUndoShuffleChangeAndPersistence() {
        launch(["-demo"])
        let original = waitForButton("tonight.log.0").label
        let second = waitForButton("tonight.log.1").label
        tap("tonight.shuffle")
        XCTAssertNotEqual(waitForButton("tonight.log.0").label, original)
        XCTAssertNotEqual(waitForButton("tonight.log.1").label, second)
        let current = waitForButton("tonight.log.1").label
        tap("tonight.log.1")
        assertText("tonight.logged")
        tap("tonight.undo")
        XCTAssertEqual(waitForButton("tonight.log.1").label, current)
        tap("tonight.log.2")
        assertText("tonight.logged")
        tap("tonight.change")
        tap("pick.leftovers")
        assertText("Leftovers")
        launch(reset: false)
        assertText("Leftovers")
    }

    func testRecordFailureLeavesCandidatesAndBackfillUsesYesterday() {
        launch(["-demo", "-fail-log"])
        tap("tonight.log.0")
        assertText("status.message")
        XCTAssertTrue(app.buttons["tonight.log.0"].exists)
        XCTAssertFalse(app.staticTexts["tonight.logged"].exists)
        tap("tab.history")
        tap("history.day.1")
        tap("pick.out")
        let yesterday = waitForButton("history.day.1")
        XCTAssertTrue(yesterday.label.contains("Ate out"))
        tap("tab.tonight")
        XCTAssertTrue(app.buttons["tonight.log.0"].exists)
    }

    func testSharePreviewAndMilestoneWithoutSystemSharePanel() {
        launch(["-demo"])
        tap("tonight.share")
        XCTAssertTrue(app.images["share.card"].waitForExistence(timeout: 12))
        tap("share.image", scroll: true)
        assertText("share.requested")
        tap("share.code", scroll: true)
        tap("share.copy", scroll: true)
        assertText("status.message")
        tap("sheet.close")
        tap("tonight.log.0")
        tap("tonight.milestone")
        XCTAssertTrue(app.images["share.card"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.switches["share.names"].exists)
    }

    func testImportConfirmDoesNotOverwriteExistingName() {
        let payload = code(#"[{"name":"ROAST CHICKEN, BROCCOLI & RICE","quick":true},{"name":"Imported stew"}]"#)
        launch(["-demo"], environment: ["UI_MENU_CODE": payload])
        tap("tab.menu")
        tap("menu.paste")
        assertText("Already on your menu or repeated in the code")
        tap("import.add", scroll: true)
        XCTAssertTrue(app.staticTexts["Imported stew"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["ROAST CHICKEN, BROCCOLI & RICE"].exists)
    }

    func testRenameArchiveAndRestoreDinner() {
        launch()
        tap("tonight.add")
        let field = app.textViews["add.names"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("Soup")
        tap("add.save")
        tap("tab.menu")
        let active = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "menu.dinner.")).firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 10))
        active.tap()
        replace(app.textFields["edit.name"], with: "Stew")
        tap("edit.save")
        XCTAssertTrue(active.waitForExistence(timeout: 10))
        XCTAssertTrue(active.label.contains("Stew"))
        active.tap()
        tap("edit.archive")
        let archive = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Archive", "edit.archive")).firstMatch
        XCTAssertTrue(archive.waitForExistence(timeout: 10))
        archive.tap()
        assertText("Your menu is empty. Add dinners or paste a menu code.")
        tap("menu.more")
        tap(Language.en.archived)
        let restore = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "archived.restore.")).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        restore.tap()
        assertText("No archived dinners.")
        tap("sheet.close")
        XCTAssertTrue(active.waitForExistence(timeout: 10))
        XCTAssertTrue(active.label.contains("Stew"))
    }

    func testExpiredPaywallClosesAndHistoryExports() {
        launch(["-demo", "-expired", "-paywall"])
        assertText("paywall.title")
        XCTAssertEqual(app.staticTexts["paywall.status"].label, "Your 30-day trial has ended.")
        XCTAssertTrue(app.buttons["paywall.restore"].exists)
        tap("sheet.close")
        XCTAssertFalse(app.buttons["tonight.quick"].exists)
        tap("tonight.log.0")
        assertText("tonight.logged")
        tap("tab.history")
        tap("history.export")
        assertText("share.requested")
    }

    func testStoreScreenshots() {
        for language in Language.allCases {
            launch(["-demo"], language: language)
            let prefix = "store-\(language.rawValue)-"
            _ = waitForButton("tonight.log.2")
            screenshot(prefix + "01-tonight")
            tap("tab.menu")
            _ = waitForButton("menu.add")
            screenshot(prefix + "02-menu")
            tap("tab.tonight")
            tap("tonight.log.0")
            assertText("tonight.logged")
            screenshot(prefix + "03-logged")
            tap("tonight.undo")
            _ = waitForButton("tonight.log.0")
            tap("tab.menu")
            tap("menu.more")
            tap(language.moreWidget)
            XCTAssertTrue(app.descendants(matching: .any)["widget.preview"].firstMatch.waitForExistence(timeout: 10))
            screenshot(prefix + "04-widget-preview")
            tap("sheet.close")
            tap("tab.tonight")
            tap("tonight.share")
            XCTAssertTrue(app.images["share.card"].waitForExistence(timeout: 15))
            _ = waitForButton("share.image", scroll: true)
            screenshot(prefix + "05-share")
        }
    }

    func testPaidScreenshot() {
        launch(["-demo", "-paywall"], language: .simplified)
        assertText("paywall.title")
        XCTAssertTrue(app.buttons["paywall.trial"].exists)
        _ = waitForButton("paywall.restore")
        screenshot("paid-01-paywall")
    }
}
