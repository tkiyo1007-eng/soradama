import Testing
import Foundation
@testable import AuroraWeather

struct WidgetDiscoveryTests {
    @Test("空玉がありWidget未設置なら案内を表示する")
    func showsGuideForAnUnconfiguredWidget() {
        #expect(TodayOrbWidgetDiscovery.shouldShow(
            hasOrb: true,
            installationState: false,
            isDismissed: false
        ))
    }

    @Test("初回記録前・設置済み・確認失敗・dismiss後は案内しない")
    func hidesGuideWhenItWouldBeIrrelevantOrRepeated() {
        #expect(!TodayOrbWidgetDiscovery.shouldShow(
            hasOrb: false,
            installationState: false,
            isDismissed: false
        ))
        #expect(!TodayOrbWidgetDiscovery.shouldShow(
            hasOrb: true,
            installationState: true,
            isDismissed: false
        ))
        #expect(!TodayOrbWidgetDiscovery.shouldShow(
            hasOrb: true,
            installationState: nil,
            isDismissed: false
        ))
        #expect(!TodayOrbWidgetDiscovery.shouldShow(
            hasOrb: true,
            installationState: false,
            isDismissed: true
        ))
    }

    @Test("Widget設置確認は最後に開始した結果だけを反映する")
    func onlyAppliesTheNewestInstallationCheck() {
        #expect(TodayOrbWidgetDiscovery.isCurrent(
            resultGeneration: 2,
            currentGeneration: 2
        ))
        #expect(!TodayOrbWidgetDiscovery.isCurrent(
            resultGeneration: 1,
            currentGeneration: 2
        ))
    }

    @Test("個別空玉の共有ラベルに日付を含める")
    func singleOrbShareLabelIncludesItsDate() {
        let orb = DailyOrb(
            dateKey: "2026-08-29",
            kind: .clear,
            tempMax: 28,
            tempMin: 20,
            humidity: 55,
            precipProbability: 10,
            placeName: "東京"
        )

        let label = OrbCollectionView.singleOrbShareAccessibilityLabel(
            for: orb,
            locale: Locale(identifier: "ja_JP")
        )

        #expect(label.contains("2026"))
        #expect(label.contains("8"))
        #expect(label.contains("29"))
        #expect(label.count > "2026 8 29".count)
    }
}
