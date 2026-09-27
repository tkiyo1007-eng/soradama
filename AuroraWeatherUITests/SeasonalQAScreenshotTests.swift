import XCTest

/// 2026年ハロウィン期間の画面確認用。通常のテスト実行では skip する。
/// 専用Simulatorで `TEST_RUNNER_SORADAMA_QA_SCREENSHOTS=1` を付けたときだけ動き、
/// 初回案内で公開都市(上越市)を自分の空に選んで天気を1回取得し、その日の空玉を記録する。
/// DEBUGビルドの `-SoradamaQASeasonalDate` は期間判定だけを差し替え、記録日は変えない。
@MainActor
final class SeasonalQAScreenshotTests: XCTestCase {
    private let joetsuResult = "citySearch.result.6825489"

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SORADAMA_QA_SCREENSHOTS"] == "1",
            "画面確認用。TEST_RUNNER_SORADAMA_QA_SCREENSHOTS=1 のときだけ実行する"
        )
        continueAfterFailure = false
    }

    func testCaptureSeasonalScreens() {
        chooseJoetsuAsMySky()

        for language in ["ja", "en"] {
            captureOnboardingSecondPage(language: language)
            for date in ["2026-09-30", "2026-10-15", "2026-11-01"] {
                let app = launchMain(language: language, seasonalDate: date)
                waitForTodayOrbCard(in: app, language: language)
                screenshot(app, name: "\(language)-main-\(date)")
                app.terminate()
            }
        }

        let large = launchMain(
            language: "ja",
            seasonalDate: "2026-10-15",
            extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        )
        waitForTodayOrbCard(in: large, language: "ja")
        screenshot(large, name: "ja-main-2026-10-15-accessibility-large")
        large.terminate()

        for language in ["ja", "en"] {
            let app = launchMain(language: language, seasonalDate: "2026-10-15")
            let card = waitForTodayOrbCard(in: app, language: language)
            card.tap()
            let share = app.buttons[language == "ja" ? "共有" : "Share"].firstMatch
            XCTAssertTrue(
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS %@", language == "ja" ? "の空玉を共有" : "Share the sky orb"))
                    .firstMatch.waitForExistence(timeout: 10) || share.waitForExistence(timeout: 1),
                "今日の空玉カードから共有ボタン付きの詳細が開く"
            )
            screenshot(app, name: "\(language)-today-orb-detail-2026-10-15")
            app.terminate()
        }
    }

    // MARK: - 手順

    private func chooseJoetsuAsMySky() {
        // 前回の確認で自分の空と今日の空玉が既にあれば、地点を選び直さない。
        let existing = launchMain(language: "ja", seasonalDate: "2026-09-30")
        let existingCard = existing.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "今日の空玉")).firstMatch
        let alreadyRecorded = existing.staticTexts["上越市"].firstMatch.waitForExistence(timeout: 15)
            && existingCard.waitForExistence(timeout: 20)
        existing.terminate()
        if alreadyRecorded { return }

        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenOnboarding", "NO", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
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
        field.tap()
        field.typeText("上越")
        let result = app.buttons[joetsuResult]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()
        // 自分の空に確定すると初回案内が閉じ、天気の取得と空玉の記録が始まる。
        XCTAssertTrue(app.buttons["設定"].waitForExistence(timeout: 15))
        _ = waitForTodayOrbCard(in: app, language: "ja")
        app.terminate()
    }

    private func captureOnboardingSecondPage(language: String) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-hasSeenOnboarding", "NO",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "ja" ? "ja_JP" : "en_US",
        ]
        app.launch()
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        next.tap()
        let message = app.staticTexts.matching(identifier: "onboarding.message")
            .matching(NSPredicate(format: "label CONTAINS %@", language == "ja" ? "左上の玉" : "top left")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        screenshot(app, name: "\(language)-onboarding-page-2")
        // 地点は選び直さず終了する。保存済みの自分の空と hasSeenOnboarding は起動引数で上書きしない。
        app.terminate()
    }

    private func launchMain(language: String, seasonalDate: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-hasSeenOnboarding", "YES",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "ja" ? "ja_JP" : "en_US",
            "-SoradamaQASeasonalDate", seasonalDate,
        ] + extra
        app.launch()
        return app
    }

    @discardableResult
    private func waitForTodayOrbCard(in app: XCUIApplication, language: String) -> XCUIElement {
        let card = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", language == "ja" ? "今日の空玉" : "Today's orb"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "今日の空玉カードが表示されない(天気取得に失敗した可能性)")
        // カードの登場演出が終わるのを待つ
        waitUntilHittable(card)
        Thread.sleep(forTimeInterval: 1.0)
        return card
    }

    private func waitUntilHittable(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func screenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
