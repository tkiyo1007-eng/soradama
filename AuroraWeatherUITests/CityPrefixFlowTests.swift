import XCTest

/// 専用Simulatorで公開都市名だけを使う。短い入力は同梱データを検索し、
/// ホーム地点確定・天気API・測位・通知は開始しない。
@MainActor
final class CityPrefixFlowTests: XCTestCase {
    func testJoetsuPrefixCanBeSavedAndReadAfterRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenOnboarding", "NO", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        defer { app.terminate() }
        openCitySearch(app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("上越")
        let result = app.buttons["citySearch.result.6825489"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["上越市"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["新潟県 / 日本"].firstMatch.exists)
        screenshot(app, name: "joetsu-prefix-result")

        let save = app.buttons["citySearch.save.6825489"]
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(app.staticTexts["マイシティ"].waitForExistence(timeout: 5))
        app.terminate()
        openCitySearch(app)
        XCTAssertTrue(app.staticTexts["上越市"].firstMatch.waitForExistence(timeout: 5))
        screenshot(app, name: "joetsu-saved-after-relaunch")
        // 保存だけではホーム地点を選択せず、初回設定は完了しない。
        app.buttons["閉じる"].firstMatch.tap()
        XCTAssertTrue(app.buttons["onboarding.city"].waitForExistence(timeout: 5))
    }

    private func openCitySearch(_ app: XCUIApplication) {
        app.launch()
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        next.tap()
        let second = app.staticTexts.matching(identifier: "onboarding.title")
            .matching(NSPredicate(format: "label == %@", "集めて、ホーム画面にも飾れる")).firstMatch
        waitUntilHittable(second)
        next.tap()
        let city = app.buttons["onboarding.city"]
        waitUntilHittable(city)
        city.tap()
    }

    private func waitUntilHittable(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func screenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
