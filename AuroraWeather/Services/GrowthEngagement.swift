import Foundation

/// App Store への導線を1か所に集約する。
/// 共有カードに描くURLとも同じアプリIDを使い、リンク先の食い違いを防ぐ。
enum AppStoreLinks {
    static let app = URL(string: "https://apps.apple.com/app/id6788443049")!
    static let writeReview = URL(string: "https://apps.apple.com/app/id6788443049?action=write-review")!
}

/// 画像だけで終わっていた共有に、空玉の特徴とクリック可能なリンクを添える。
/// 共有先によって本文が省略される場合に備え、画像内のURL表記は引き続き残す。
enum SoradamaShareContent {
    static var subject: String {
        String(localized: "空を集める天気アプリ「空玉」")
    }

    static var message: String {
        String(localized: "毎日の空を、小さなガラス玉に残せる天気アプリです。")
    }

    static var messageWithStoreLink: String {
        "\(message)\n\(AppStoreLinks.app.absoluteString)"
    }
}

/// 「今日の空玉」は現在地（先頭ページ）の天気からだけ作られる。
/// 保存した別都市のページにも同じ玉を表示すると、その都市の記録だと誤解されるため、
/// カードを出せる条件を画面から切り離して固定する。
enum TodayOrbCardPolicy {
    static func shouldShow(
        pageID: String,
        primaryPageID: String?,
        hasTodayOrb: Bool
    ) -> Bool {
        hasTodayOrb && pageID == primaryPageID
    }
}

/// 評価依頼は、使い始めではなく「空を集める習慣」ができた成功直後だけ候補にする。
/// StoreKit側の表示回数制限に加え、アプリ側でも同一バージョン1回・120日間隔に抑える。
struct ReviewPromptPolicy {
    static let minimumStreak = 3
    static let cooldown: TimeInterval = 120 * 24 * 60 * 60

    private static let lastRequestedVersionKey = "soradama.reviewPrompt.lastRequestedVersion"
    private static let lastRequestedDateKey = "soradama.reviewPrompt.lastRequestedDate"

    private let defaults: UserDefaults
    private let currentVersion: String
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        currentVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown",
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.now = now
    }

    /// 条件を満たした最初の呼び出しだけを予約し、同じ表示機会の二重発火を防ぐ。
    @discardableResult
    func reserveIfEligible(for event: OrbRecordResult) -> Bool {
        guard event.isFirstToday,
              event.streak >= Self.minimumStreak,
              !event.isMilestone,
              event.solarTerm == nil,
              !event.isFullMoon else {
            return false
        }

        guard defaults.string(forKey: Self.lastRequestedVersionKey) != currentVersion else {
            return false
        }

        let requestDate = now()
        if let previousDate = defaults.object(forKey: Self.lastRequestedDateKey) as? Date,
           requestDate.timeIntervalSince(previousDate) < Self.cooldown {
            // 端末時計が巻き戻った場合も負の経過時間になるため、保守的に抑止される。
            return false
        }

        defaults.set(currentVersion, forKey: Self.lastRequestedVersionKey)
        defaults.set(requestDate, forKey: Self.lastRequestedDateKey)
        return true
    }
}
