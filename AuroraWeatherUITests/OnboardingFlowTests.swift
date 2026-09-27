import XCTest

/// Run on a dedicated Simulator. Launch arguments override the onboarding flag
/// without deleting saved preferences, places, or orbs. No city search query or
/// current-location request is issued by these tests.
@MainActor
final class OnboardingFlowTests: XCTestCase {
    private let titles = [
        "天気を取得できた日が、空玉になる",
        "集めて、ホーム画面にも飾れる",
        "あなたの空を教えてください"
    ]
    private let messages = [
        "「自分の空」の天気を取得できたとき、端末の日付で1日1個の空玉が残ります",
        "毎日の空をカレンダーで振り返り、\n今日の空玉をウィジェットで楽しめます",
        "現在地を使うか、都市を選んで\nあなたの空を決められます(あとから変更できます)"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Keep this launch-to-first-action check short so cold-start input failures
    /// are not hidden by screenshots, retries, or an arbitrary settling delay.
    func testSingleNextTapsReachEachPageImmediatelyAfterLaunch() {
        let app = launchOnboarding(contentSize: "UICTContentSizeCategoryL")
        defer { app.terminate() }
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.isHittable)
        for page in 1..<3 {
            next.tap()
            let title = app.staticTexts.matching(identifier: "onboarding.title")
                .matching(NSPredicate(format: "label == %@", titles[page])).firstMatch
            waitUntilHittable(title)
            assertPage(page, in: app)
            attachScreenshot(app, named: "single-tap-page-\(page + 1)")
        }
        XCTAssertTrue(app.buttons["onboarding.city"].isHittable)
        XCTAssertFalse(next.exists)
        assertMainScreenIsHidden(in: app)
    }

    func testNormalTextCanChooseCityAndCancelWithoutFinishingOnboarding() {
        let app = launchOnboarding(contentSize: "UICTContentSizeCategoryL")
        defer { app.terminate() }
        assertMainScreenIsHidden(in: app)

        for page in 0..<3 {
            assertPage(page, in: app)
            XCTAssertTrue(app.staticTexts.matching(identifier: "onboarding.title")
                .matching(NSPredicate(format: "label == %@", titles[page])).firstMatch.isHittable)
            attachScreenshot(app, named: "normal-page-\(page + 1)")
            if page < 2 {
                tapReachable(app.buttons["onboarding.next"], in: app)
            }
        }

        if app.frame.height <= 667 {
            let back = app.buttons["onboarding.back"]
            reveal(back, in: app)
            waitUntilHittable(back)
            XCTAssertGreaterThanOrEqual(back.frame.width, 44,
                                        "The compact-layout Back button needs a 44-point-wide hit target")
            XCTAssertGreaterThanOrEqual(back.frame.height, 44,
                                        "The compact-layout Back button needs a 44-point-high hit target")
            attachScreenshot(app, named: "compact-back-hit-target")
            // Tap the padding near the top edge once, not the text's center.
            // Retrying a missed tap would conceal a too-small hit target.
            back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: 3)).tap()
            assertPage(1, in: app)
            let previousTitle = app.staticTexts.matching(identifier: "onboarding.title")
                .matching(NSPredicate(format: "label == %@", titles[1])).firstMatch
            waitUntilHittable(previousTitle)
            tapReachable(app.buttons["onboarding.next"], in: app)
            assertPage(2, in: app)
        }

        assertCitySheetCanBeCancelled(in: app)
    }

    func testLargestStandardTextFitsAllPagesAndCanCancelCitySelection() {
        let normalApp = launchOnboarding(contentSize: "UICTContentSizeCategoryL")
        assertPage(0, in: normalApp)
        let normalTitleHeight = normalApp.staticTexts["onboarding.title"].firstMatch.frame.height
        let normalMessageHeight = normalApp.staticTexts["onboarding.message"].firstMatch.frame.height
        normalApp.terminate()

        let app = launchOnboarding(contentSize: "UICTContentSizeCategoryXXXL")
        defer { app.terminate() }
        assertMainScreenIsHidden(in: app)
        assertPage(0, in: app)
        XCTAssertGreaterThan(app.staticTexts["onboarding.title"].firstMatch.frame.height,
                             normalTitleHeight * 1.1)
        XCTAssertGreaterThan(app.staticTexts["onboarding.message"].firstMatch.frame.height,
                             normalMessageHeight * 1.1)

        for page in 0..<3 {
            assertPage(page, in: app)
            let title = app.staticTexts.matching(identifier: "onboarding.title")
                .matching(NSPredicate(format: "label == %@", titles[page])).firstMatch
            let message = app.staticTexts.matching(identifier: "onboarding.message")
                .matching(NSPredicate(format: "label == %@", messages[page])).firstMatch
            let viewport = app.frame.insetBy(dx: -1, dy: -1)
            XCTAssertTrue(viewport.contains(title.frame), "The complete title must fit within the screen")
            XCTAssertTrue(viewport.contains(message.frame), "The complete explanation must fit within the screen")
            XCTAssertTrue(title.isHittable)
            XCTAssertTrue(message.isHittable)
            let firstAction = app.buttons[page < 2 ? "onboarding.next" : "onboarding.currentLocation"]
            XCTAssertLessThanOrEqual(message.frame.maxY, firstAction.frame.minY + 1,
                                    "The explanation must not overlap the page controls")
            attachScreenshot(app, named: "largest-standard-text-page-\(page + 1)")
            if page < 2 {
                tapReachable(app.buttons["onboarding.next"], in: app)
            }
        }

        assertCitySheetCanBeCancelled(in: app)
    }

    func testMaximumTextExpandsAndKeepsAllPagesAndCityChoiceReachable() {
        let normalApp = launchOnboarding(contentSize: "UICTContentSizeCategoryL")
        assertPage(0, in: normalApp)
        let normalTitleHeight = normalApp.staticTexts["onboarding.title"].firstMatch.frame.height
        let normalMessageHeight = normalApp.staticTexts["onboarding.message"].firstMatch.frame.height
        normalApp.terminate()

        let app = launchOnboarding(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        defer { app.terminate() }
        assertMainScreenIsHidden(in: app)
        assertPage(0, in: app)

        let title = app.staticTexts["onboarding.title"].firstMatch
        let message = app.staticTexts["onboarding.message"].firstMatch
        // Full accessibility labels alone do not prove the rendered text is
        // untruncated. Verify that the layout actually grows for the large font.
        XCTAssertGreaterThan(title.frame.height, normalTitleHeight * 1.5)
        XCTAssertGreaterThan(message.frame.height, normalMessageHeight * 1.5)

        for page in 0..<3 {
            assertPage(page, in: app)
            reveal(app.staticTexts["onboarding.title"].firstMatch, in: app)
            attachScreenshot(app, named: "maximum-text-page-\(page + 1)-top")
            if page < 2 {
                reveal(app.buttons["onboarding.next"], in: app)
                attachScreenshot(app, named: "maximum-text-page-\(page + 1)-controls")
                app.buttons["onboarding.next"].tap()
            }
        }

        // Large-text mode has an explicit backwards route in place of relying
        // on a horizontal page gesture.
        tapReachable(app.buttons["onboarding.back"], in: app)
        assertPage(1, in: app)
        tapReachable(app.buttons["onboarding.next"], in: app)
        assertPage(2, in: app)
        reveal(app.buttons["onboarding.city"], in: app)
        attachScreenshot(app, named: "maximum-text-page-3-city-choice")
        assertCitySheetCanBeCancelled(in: app)
    }

    func testEnglishMaximumTextCanReadPagesAndCancelCitySelection() {
        let app = launchOnboarding(contentSize: "UICTContentSizeCategoryAccessibilityXXXL", language: "en")
        defer { app.terminate() }
        let englishTitles = [
            "A successful weather update becomes an orb",
            "Collect your skies and keep one on your Home Screen",
            "Tell us where your sky is"
        ]
        assertMainScreenIsHidden(in: app)
        for page in 0..<3 {
            let title = app.staticTexts["onboarding.title"].firstMatch
            let predicate = NSPredicate(format: "label == %@", englishTitles[page])
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: title)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
            reveal(title, in: app)
            attachScreenshot(app, named: "english-maximum-text-page-\(page + 1)")
            if page < 2 {
                tapReachable(app.buttons["onboarding.next"], in: app)
            }
        }
        tapReachable(app.buttons["onboarding.city"], in: app)
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(app.buttons["onboarding.city"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["onboarding.title"].firstMatch.label, englishTitles[2])
        assertMainScreenIsHidden(in: app)
    }

    private func launchOnboarding(contentSize: String, language: String = "ja") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-hasSeenOnboarding", "NO",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "ja" ? "ja_JP" : "en_US",
            "-UIPreferredContentSizeCategoryName", contentSize
        ]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 15))
        return app
    }

    private func assertPage(_ page: Int, in app: XCUIApplication,
                            file: StaticString = #filePath, line: UInt = #line) {
        // PageTabViewは画面外のページを保持するため、単なるfirstMatchでは
        // 前ページを拾う。期待するページを完全なラベルで特定する。
        let title = app.staticTexts.matching(identifier: "onboarding.title")
            .matching(NSPredicate(format: "label == %@", titles[page])).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), file: file, line: line)
        let message = app.staticTexts.matching(identifier: "onboarding.message")
            .matching(NSPredicate(format: "label == %@", messages[page])).firstMatch
        XCTAssertEqual(message.label, messages[page], file: file, line: line)
        XCTAssertGreaterThan(title.frame.height, 0, file: file, line: line)
        XCTAssertGreaterThan(message.frame.height, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(title.frame.maxY, message.frame.minY + 1,
                                "Title and explanation must not overlap", file: file, line: line)
    }

    private func assertMainScreenIsHidden(in app: XCUIApplication,
                                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(app.buttons["都市を検索"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["設定"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["Search cities"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["Settings"].exists, file: file, line: line)
    }

    private func assertCitySheetCanBeCancelled(in app: XCUIApplication) {
        tapReachable(app.buttons["onboarding.city"], in: app)
        let cityNavigationBar = app.navigationBars.firstMatch
        let close = cityNavigationBar.buttons["閉じる"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.exists)
        attachScreenshot(app, named: "city-sheet-without-location-permission")
        waitUntilHittable(searchField)
        searchField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "Focusing city search must expose the keyboard")
        attachScreenshot(app, named: "city-sheet-keyboard-before-cancel")
        // The tested native search UI exposes Cancel on iOS 18 and Close on iOS 27.
        // End search first, verify that transition, then dismiss the city sheet
        // if it remains. These are distinct transitions, not retries of a tap.
        let cancelSearch = app.buttons["キャンセル"].firstMatch
        let exitAvailable = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in close.isHittable || cancelSearch.isHittable },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [exitAvailable], timeout: 5), .completed)
        if cancelSearch.isHittable {
            cancelSearch.tap()
        } else {
            waitUntilHittable(close)
            close.tap()
        }
        waitUntilGone(app.keyboards.firstMatch)
        if cityNavigationBar.exists {
            attachScreenshot(app, named: "city-sheet-after-ending-search")
            waitUntilHittable(close)
            close.tap()
        }
        waitUntilGone(cityNavigationBar)
        waitUntilGone(searchField)
        waitUntilGone(app.keyboards.firstMatch)
        XCTAssertTrue(app.buttons["onboarding.city"].waitForExistence(timeout: 5))
        assertPage(2, in: app)
        assertMainScreenIsHidden(in: app)
        reveal(app.buttons["onboarding.currentLocation"], in: app)
        XCTAssertTrue(app.buttons["onboarding.currentLocation"].isEnabled)
        attachScreenshot(app, named: "onboarding-preserved-after-city-cancel")
    }

    private func tapReachable(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        element.tap()
    }

    private func waitUntilHittable(_ element: XCUIElement,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "The control must be reachable after layout settles", file: file, line: line)
    }

    private func waitUntilGone(_ element: XCUIElement,
                               file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "The dismissed UI must not remain present", file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        for _ in 0..<8 where !element.isHittable {
            if element.frame.minY < app.frame.minY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable, "The onboarding control/text must be reachable by scrolling",
                      file: file, line: line)
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
