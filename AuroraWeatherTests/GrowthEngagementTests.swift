import Testing
import Foundation
@testable import AuroraWeather

struct GrowthEngagementTests {
    @Test("今日の空玉がない日と2日未満では評価依頼を予約しない")
    func reviewPromptRequiresTodayOrbAndStreak() {
        let defaults = Self.makeDefaults()
        let policy = ReviewPromptPolicy(defaults: defaults, currentVersion: "1.8.5")

        #expect(!policy.reserveIfEligible(todayOrb: nil, streak: 5))
        #expect(!policy.reserveIfEligible(todayOrb: Self.orb(), streak: 1))
    }

    @Test("2日目以降は、その日何回目の起動でも一度だけ予約する")
    func reviewPromptIsReservedOncePerVersion() {
        let defaults = Self.makeDefaults()
        let policy = ReviewPromptPolicy(defaults: defaults, currentVersion: "1.8.5")

        #expect(policy.reserveIfEligible(todayOrb: Self.orb(), streak: 2))
        #expect(!policy.reserveIfEligible(todayOrb: Self.orb(), streak: 2))
    }

    @Test("お祝いの演出が出る日は評価依頼をしない")
    func reviewPromptAvoidsCelebrationDays() throws {
        let defaults = Self.makeDefaults()
        let policy = ReviewPromptPolicy(defaults: defaults, currentVersion: "1.8.5")

        #expect(!policy.reserveIfEligible(todayOrb: Self.orb(isMilestone: true), streak: 7))

        let solarTermDay = Self.orb(dateKey: "2026-02-04")
        try #require(solarTermDay.solarTerm != nil)
        #expect(!policy.reserveIfEligible(todayOrb: solarTermDay, streak: 4))

        let fullMoonNight = Self.orb(dateKey: "2026-09-26", timeOfDay: .night)
        try #require(fullMoonNight.moonPhase == .fullMoon)
        #expect(!policy.reserveIfEligible(todayOrb: fullMoonNight, streak: 4))
    }

    @Test("バージョンが変わっても120日間は再依頼しない")
    func reviewPromptHonorsCooldownAcrossVersions() {
        let defaults = Self.makeDefaults()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = ReviewPromptPolicy(
            defaults: defaults,
            currentVersion: "1.8.5",
            now: { start }
        )
        #expect(first.reserveIfEligible(todayOrb: Self.orb(), streak: 3))

        let tooSoon = ReviewPromptPolicy(
            defaults: defaults,
            currentVersion: "1.9.0",
            now: { start.addingTimeInterval(119 * 24 * 60 * 60) }
        )
        #expect(!tooSoon.reserveIfEligible(todayOrb: Self.orb(), streak: 4))

        let afterCooldown = ReviewPromptPolicy(
            defaults: defaults,
            currentVersion: "1.9.0",
            now: { start.addingTimeInterval(120 * 24 * 60 * 60) }
        )
        #expect(afterCooldown.reserveIfEligible(todayOrb: Self.orb(), streak: 4))
    }

    @Test("端末時計が巻き戻った場合は評価依頼を抑止する")
    func reviewPromptRejectsClockRollback() {
        let defaults = Self.makeDefaults()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = ReviewPromptPolicy(
            defaults: defaults,
            currentVersion: "1.8.5",
            now: { start }
        )
        #expect(first.reserveIfEligible(todayOrb: Self.orb(), streak: 3))

        let rolledBack = ReviewPromptPolicy(
            defaults: defaults,
            currentVersion: "2.0.0",
            now: { start.addingTimeInterval(-60) }
        )
        #expect(!rolledBack.reserveIfEligible(todayOrb: Self.orb(), streak: 4))
    }

    @Test("App Storeとレビューのリンクが正しい")
    func appStoreLinksAreValid() {
        #expect(AppStoreLinks.app.scheme == "https")
        #expect(AppStoreLinks.app.absoluteString.contains("id6788443049"))
        #expect(AppStoreLinks.writeReview.scheme == "https")
        #expect(AppStoreLinks.writeReview.query?.contains("action=write-review") == true)
    }

    @Test("共有本文に空玉の説明とクリック可能なリンクを含める")
    func shareContentIncludesInvitationAndStoreLink() {
        #expect(!SoradamaShareContent.subject.isEmpty)
        #expect(!SoradamaShareContent.message.isEmpty)
        #expect(SoradamaShareContent.messageWithStoreLink.contains(SoradamaShareContent.message))
        #expect(SoradamaShareContent.messageWithStoreLink.contains(AppStoreLinks.app.absoluteString))
    }

    @Test("今日の空玉Widget用URLスキームがアプリに登録されている")
    func widgetDeepLinkSchemeIsRegistered() {
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = urlTypes?.flatMap { urlType in
            urlType["CFBundleURLSchemes"] as? [String] ?? []
        } ?? []

        #expect(schemes.contains(SoradamaURL.scheme))
        #expect(SoradamaURL.opensCollection(SoradamaURL.collection))
        #expect(!SoradamaURL.opensCollection(URL(string: "soradama://settings")!))
        #expect(!SoradamaURL.opensCollection(URL(string: "soradama://collection/history")!))
        #expect(!SoradamaURL.opensCollection(URL(string: "soradama://collection?source=external")!))
    }

    @Test("今日の空玉カードは記録元の先頭ページだけに出す")
    func todayOrbCardOnlyAppearsOnPrimaryPage() {
        #expect(TodayOrbCardPolicy.shouldShow(
            pageID: "current",
            primaryPageID: "current",
            hasTodayOrb: true
        ))
        #expect(!TodayOrbCardPolicy.shouldShow(
            pageID: "saved-city",
            primaryPageID: "current",
            hasTodayOrb: true
        ))
        #expect(!TodayOrbCardPolicy.shouldShow(
            pageID: "current",
            primaryPageID: "current",
            hasTodayOrb: false
        ))
        #expect(!TodayOrbCardPolicy.shouldShow(
            pageID: "current",
            primaryPageID: nil,
            hasTodayOrb: true
        ))
    }

    private static func orb(
        dateKey: String = "2026-10-20",
        isMilestone: Bool = false,
        timeOfDay: TimeOfDay = .day
    ) -> DailyOrb {
        DailyOrb(
            dateKey: dateKey,
            kind: .clear,
            tempMax: 22,
            tempMin: 14,
            humidity: 55,
            precipProbability: 0,
            placeName: "",
            isMilestone: isMilestone,
            timeOfDay: timeOfDay
        )
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "GrowthEngagementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
