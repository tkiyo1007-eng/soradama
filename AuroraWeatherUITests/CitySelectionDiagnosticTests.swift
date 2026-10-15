import XCTest

/// 調査用。初回案内から「上越」を選んだ直後に画面がどう変わるかを、1秒ごとの画面写真と
/// 要素ツリーで記録する。通常のテスト実行では skip する。
/// `TEST_RUNNER_SORADAMA_DIAG_CITY=1` のときだけ動く。
@MainActor
final class CitySelectionDiagnosticTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SORADAMA_DIAG_CITY"] == "1",
            "調査用。TEST_RUNNER_SORADAMA_DIAG_CITY=1 のときだけ実行する"
        )
        continueAfterFailure = true
    }

    func testRecordWhatHappensAfterChoosingCity() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        defer { app.terminate() }

        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        next.tap()
        waitUntilHittable(next)
        next.tap()
        let city = app.buttons["onboarding.city"]
        waitUntilHittable(city)
        city.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        sleep(1)
        field.tap()
        field.typeText("上越")
        let result = app.buttons["citySearch.result.6825489"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        record(app, "before-tap")
        let frame = result.frame
        let save = app.buttons["citySearch.save.6825489"].firstMatch
        attachText("result frame: \(frame)\nsave frame: \(save.exists ? "\(save.frame)" : "none")\nhittable: \(result.isHittable)", name: "frames")
        result.tap()
        for second in 1...8 {
            sleep(1)
            record(app, "after-tap-\(second)s")
            if app.buttons["設定"].exists { break }
        }
    }

    private func record(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "diag-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
        let summary = "sheets: \(app.sheets.count), alerts: \(app.alerts.count), 設定: \(app.buttons["設定"].exists), onboarding.city: \(app.buttons["onboarding.city"].exists), searchField: \(app.searchFields.count), result: \(app.buttons["citySearch.result.6825489"].exists)\n\n"
        attachText(summary + app.debugDescription, name: "tree-\(name)")
    }

    private func attachText(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntilHittable(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }
}
