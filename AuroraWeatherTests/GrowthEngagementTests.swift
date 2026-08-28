import Testing
import Foundation
@testable import AuroraWeather

struct GrowthEngagementTests {
    @Test("3日未満では評価依頼を予約しない")
    func reviewPromptRequiresAStreak() {
        let defaults = Self.makeDefaults()
        let policy = ReviewPromptPolicy(defaults: defaults, currentVersion: "1.8.0")

        #expect(!policy.reserveIfEligible(for: Self.event(streak: 1)))
        #expect(!policy.reserveIfEligible(for: Self.event(streak: 2)))
    }

    @Test("3日目の通常記録で一度だけ評価依頼を予約する")
    func reviewPromptIsReservedOncePerVersion() {
        let defaults = Self.makeDefaults()
        let policy = ReviewPromptPolicy(defaults: defaults, currentVersion: "1.8.0")
        let event = Self.event(streak: 3)

        #expect(policy.reserveIfEligible(for: event))
        #expect(!policy.reserveIfEligible(for: event))
    }

    @Test("同日の上書きと特別な演出中は評価依頼をしない")
    func reviewPromptAvoidsBadMoments() {
        let defaults = Self.makeDefaults()
        let policy = ReviewPromptPolicy(defaults: defaults, currentVersion: "1.8.0")

        #expect(!policy.reserveIfEligible(for: Self.event(streak: 4, isFirstToday: false)))
        #expect(!policy.reserveIfEligible(for: Self.event(streak: 7, isMilestone: true)))
        #expect(!policy.reserveIfEligible(for: Self.event(streak: 4, isFullMoon: true)))
        #expect(!policy.reserveIfEligible(for: Self.event(streak: 4, solarTerm: .risshun)))
    }

    @Test("バージョンが変わっても120日間は再依頼しない")
    func reviewPromptHonorsCooldownAcrossVersions() {
        let defaults = Self.makeDefaults()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = ReviewPromptPolicy(
            defaults: defaults,
            currentVersion: "1.8.0",
            now: { start }
        )
        #expect(first.reserveIfEligible(for: Self.event(streak: 3)))

        let tooSoon = ReviewPromptPolicy(
            defaults: defaults,
            currentVersion: "1.9.0",
            now: { start.addingTimeInterval(119 * 24 * 60 * 60) }
        )
        #expect(!tooSoon.reserveIfEligible(for: Self.event(streak: 4)))

        let afterCooldown = ReviewPromptPolicy(
            defaults: defaults,
            currentVersion: "1.9.0",
            now: { start.addingTimeInterval(120 * 24 * 60 * 60) }
        )
        #expect(afterCooldown.reserveIfEligible(for: Self.event(streak: 4)))
    }

    @Test("端末時計が巻き戻った場合は評価依頼を抑止する")
    func reviewPromptRejectsClockRollback() {
        let defaults = Self.makeDefaults()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = ReviewPromptPolicy(
            defaults: defaults,
            currentVersion: "1.8.0",
            now: { start }
        )
        #expect(first.reserveIfEligible(for: Self.event(streak: 3)))

        let rolledBack = ReviewPromptPolicy(
            defaults: defaults,
            currentVersion: "2.0.0",
            now: { start.addingTimeInterval(-60) }
        )
        #expect(!rolledBack.reserveIfEligible(for: Self.event(streak: 4)))
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

    private static func event(
        streak: Int,
        isFirstToday: Bool = true,
        isMilestone: Bool = false,
        isFullMoon: Bool = false,
        solarTerm: SolarTerm? = nil
    ) -> OrbRecordResult {
        OrbRecordResult(
            isFirstToday: isFirstToday,
            streak: streak,
            isMilestone: isMilestone,
            isNewKind: false,
            solarTerm: solarTerm,
            isFullMoon: isFullMoon
        )
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "GrowthEngagementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
