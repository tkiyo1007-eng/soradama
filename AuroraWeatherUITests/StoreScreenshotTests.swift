import XCTest

/// App Store 用のスクリーンショットを撮る。通常のテスト実行では skip する。
/// 専用 Simulator で `TEST_RUNNER_SORADAMA_STORE_SCREENSHOTS=1` を付けたときだけ動く。
/// 前提: Simulator のアプリデータに、2026年9月の空玉の見本を入れておく
/// (`defaults write com.tkiyo1007.soradama soradama.dailyOrbs -data ...`)。
/// 季節の演出がストアの画像に写らないよう、DEBUG の期間判定を 9月20日に固定する。
@MainActor
final class StoreScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SORADAMA_STORE_SCREENSHOTS"] == "1",
            "ストア画像用。TEST_RUNNER_SORADAMA_STORE_SCREENSHOTS=1 のときだけ実行する"
        )
        continueAfterFailure = false
    }

    func testCaptureStoreScreens() {
        for language in ["ja", "en"] {
            capture(language: language)
        }
    }

    private func capture(language: String) {
        let ja = language == "ja"
        let app = XCUIApplication()
        app.launchArguments = [
            "-hasSeenOnboarding", "YES",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", ja ? "ja_JP" : "en_US",
            "-SoradamaQASeasonalDate", "2026-09-20",
        ]
        app.launch()
        defer { app.terminate() }

        let card = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", ja ? "今日の空玉" : "Today's orb"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "今日の空玉カードが表示されない")
        settle()
        screenshot(app, "\(language)-home")

        // 上部の玉からコレクションを開き、見本の入った9月へ戻る。
        let collectionButton = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", ja ? "空玉コレクションを開く" : "Open the sky collection"))
            .firstMatch
        XCTAssertTrue(collectionButton.waitForExistence(timeout: 5))
        collectionButton.tap()
        let previous = app.buttons["chevron.left"].firstMatch
        XCTAssertTrue(previous.waitForExistence(timeout: 10))
        previous.tap()
        settle()
        let dismissWidgetGuide = app.buttons[ja ? "ウィジェットの案内を閉じる" : "Dismiss the widget tip"].firstMatch
        if dismissWidgetGuide.exists { dismissWidgetGuide.tap(); settle() }
        screenshot(app, "\(language)-collection")

        let lookBack = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", ja ? "この月をふりかえる" : "Look back"))
            .firstMatch
        XCTAssertTrue(lookBack.waitForExistence(timeout: 5))
        lookBack.tap()
        settle(2)
        screenshot(app, "\(language)-month")
    }

    private func settle(_ seconds: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
