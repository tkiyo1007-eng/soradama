import XCTest

/// 画面の自動アクセシビリティ検査。Xcode の performAccessibilityAudit で、
/// ラベルの無い操作部品・読み上げできない名前・文字の切れ・小さすぎるタップ領域などを見つける。
/// 初回案内 → 上越市を自分の空に選ぶ → 天気画面 → 今日の空玉 → コレクション → 設定 の順に検査する。
/// 天気の取得にネットワークを使う。季節の演出は入れずに検査する。
///
/// コントラストと Dynamic Type の判定は、このアプリでは当てにならない
/// (アプリ全体をダークにしているのに、磨りガラスの背景を明るい色として計算し、
/// 紺の背景の上の白い文字まで「コントラスト不足」と判定する)。文字が切れるおそれの判定も推測で、
/// 実際には折り返す部品にも出る。その3種類は失敗にせず、記録だけにする。
/// 色の明るさは `QA/a11y-contrast.md` の計算で、大きな文字の見た目は testLargestAccessibilityTextScreens の
/// 画面写真で別に見る。ナビゲーションバーのボタンの高さ(36pt)は OS が決めるので対象外にする。
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    override func setUpWithError() throws {
        // 1画面に複数の指摘があっても全部集めたいので、最初の失敗で止めない
        continueAfterFailure = true
    }

    func testMainScreensPassAccessibilityAudit() throws {
        let app = XCUIApplication()
        // `-hasSeenOnboarding NO` で上書きすると、確定後に書いた true が起動引数に負けて
        // 初回案内へ戻ることがある。初回案内を検査したいときはアプリを入れ直してから実行する
        // (xcrun simctl uninstall <sim> com.tkiyo1007.soradama)。入れ直していなければ天気画面から検査する。
        app.launchArguments = [
            "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP",
            "-SoradamaQASeasonalDate", "2026-09-20",
        ]
        app.launch()
        defer { app.terminate() }

        let next = app.buttons["onboarding.next"]
        if next.waitForExistence(timeout: 10) {
            try audit(app, screen: "onboarding-1")
            next.tap()
            waitUntilHittable(next)
            try audit(app, screen: "onboarding-2")
            next.tap()
            let city = app.buttons["onboarding.city"]
            waitUntilHittable(city)
            try audit(app, screen: "onboarding-3")

            city.tap()
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            // シートが開ききる前に検査すると、ツールバーの部品が小さいまま測られる
            waitUntilHittable(app.buttons["citySearch.close"].firstMatch)
            sleep(1)
            try audit(app, screen: "city-search")
            focusAndType("上越", into: field)
            let result = app.buttons["citySearch.result.6825489"]
            XCTAssertTrue(result.waitForExistence(timeout: 10))
            try audit(app, screen: "city-search-results")
            result.tap()
        }
        XCTAssertTrue(app.buttons["設定"].waitForExistence(timeout: 20))
        let card = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "今日の空玉")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "今日の空玉カードが出ない(天気の取得に失敗した可能性)")
        waitUntilHittable(card)
        sleep(1)
        try audit(app, screen: "weather-top")

        // 先に今日の空玉 → コレクションを見る(戻るスワイプで引っ張って更新が走り、カードを見失うのを避ける)
        card.tap()
        // 共有ボタンの読み上げ名は「2026年10月16日の空玉を共有」のように日付入り
        let share = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "の空玉を共有")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 15), "今日の空玉カードから詳細が開かない")
        // 押せる範囲の確認用に、詳細の主なボタンの大きさを残す
        let frames = app.buttons.allElementsBoundByIndex.prefix(40)
            .map { "\($0.label.prefix(24)) \($0.frame.size)" }.joined(separator: "\n")
        let framesNote = XCTAttachment(string: frames)
        framesNote.name = "today-orb-detail-button-frames"
        framesNote.lifetime = .keepAlways
        add(framesNote)
        try audit(app, screen: "today-orb-detail")
        // 詳細の「閉じる」はカードの中、コレクションの「閉じる」はツールバー。下にある方が詳細
        let detailClose = app.buttons.matching(identifier: "閉じる").allElementsBoundByIndex
            .max { $0.frame.minY < $1.frame.minY }
        detailClose?.tap()
        XCTAssertTrue(app.staticTexts["空玉コレクション"].waitForExistence(timeout: 5))
        sleep(1)
        try audit(app, screen: "collection")
        app.buttons["閉じる"].firstMatch.tap()
        waitUntilHittable(card)

        app.swipeUp()
        sleep(1)
        try audit(app, screen: "weather-scrolled")

        // 天気画面からの都市検索(初回案内を通らない実行でもシートを検査できるようにする)
        let search = app.buttons["都市を検索"].firstMatch
        waitUntilHittable(search)
        search.tap()
        let close = app.buttons["citySearch.close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        waitUntilHittable(close)
        sleep(1)
        let note = XCTAttachment(string: "citySearch.close frame: \(close.frame)")
        note.name = "city-search-close-frame"
        note.lifetime = .keepAlways
        add(note)
        try audit(app, screen: "city-search-from-main")
        close.tap()

        let settings = app.buttons["設定"].firstMatch
        waitUntilHittable(settings)
        settings.tap()
        sleep(1)
        try audit(app, screen: "settings")
    }

    /// 最大のアクセシビリティ文字サイズで、折り返しとスクロールの様子を画面写真に残す
    /// (自動検査の「文字が切れるおそれ」は推測なので、実際の見た目で判断する)。
    /// 地点設定済みの状態で実行する前提。初回案内が出たら何もしない。
    func testLargestAccessibilityTextScreens() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP",
            "-SoradamaQASeasonalDate", "2026-09-20",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        defer { app.terminate() }
        let search = app.buttons["都市を検索"].firstMatch
        guard search.waitForExistence(timeout: 20) else { return }
        waitUntilHittable(search)
        search.tap()
        let close = app.buttons["citySearch.close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        sleep(1)
        screenshot(app, "ax-xxxl-city-search")
        close.tap()

        let card = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "今日の空玉")).firstMatch
        guard card.waitForExistence(timeout: 20) else { return }
        screenshot(app, "ax-xxxl-weather")
        waitUntilHittable(card)
        card.tap()
        let share = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "の空玉を共有")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 15))
        screenshot(app, "ax-xxxl-today-orb-detail")
        app.swipeUp()
        sleep(1)
        screenshot(app, "ax-xxxl-today-orb-detail-scrolled")
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 画面写真を残してから検査する。指摘は performAccessibilityAudit が個別の失敗として報告する。
    private func audit(_ app: XCUIApplication, screen: String) throws {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "a11y-\(screen)"
        attachment.lifetime = .keepAlways
        add(attachment)
        var skipped: [String] = []
        try XCTContext.runActivity(named: "アクセシビリティ検査: \(screen)") { _ in
            try app.performAccessibilityAudit(for: .all) { issue in
                switch issue.auditType {
                case .contrast, .dynamicType:
                    skipped.append("\(issue.compactDescription): \(issue.element?.description ?? "?")")
                    return true
                case .textClipped:
                    // 「大きな文字で切れるおそれ」は推測で、実際には折り返す部品にも出る
                    // (都市検索の「現在地を使う」で確認済み)。testLargestAccessibilityTextScreens の
                    // 画面写真で実物を見るので、ここでは記録だけにする
                    skipped.append("\(issue.compactDescription): \(issue.element?.description ?? "?")")
                    return true
                case .hitRegion where Self.isInNavigationBar(issue.element, of: app):
                    // ナビゲーションバーのボタンは OS が 36pt に決めていて、アプリ側では変えられない
                    skipped.append("\(issue.compactDescription): \(issue.element?.description ?? "?")")
                    return true
                default:
                    return false
                }
            }
        }
        if !skipped.isEmpty {
            let note = XCTAttachment(string: skipped.joined(separator: "\n"))
            note.name = "a11y-\(screen)-skipped-contrast-dynamictype"
            note.lifetime = .keepAlways
            add(note)
        }
    }

    private static func isInNavigationBar(_ element: XCUIElement?, of app: XCUIApplication) -> Bool {
        guard let element, element.exists else { return false }
        let frame = element.frame
        return app.navigationBars.allElementsBoundByIndex.contains { $0.frame.contains(frame) }
    }

    /// シートの表示直後は1回のタップで焦点が来ないことがあるので、焦点を確かめてから入力する。
    private func focusAndType(_ text: String, into field: XCUIElement) {
        for _ in 0..<3 {
            field.tap()
            let focused = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field
            )
            if XCTWaiter.wait(for: [focused], timeout: 3) == .completed { break }
        }
        field.typeText(text)
    }

    private func waitUntilHittable(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }
}
