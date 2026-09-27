import Testing
import Foundation
@testable import AuroraWeather

/// JMAの補完取得に失敗したとき、欠測を降水なし・外干し日和と扱わない。
@MainActor
struct WeatherAvailabilityTests {
    @Test("降水確率の欠測は0%と表示・読み上げしない")
    func missingUmbrellaProbability() {
        let view = UmbrellaIndexView(probability: nil)

        #expect(view.valueText == "—")
        #expect(view.accessibilityText == String(localized: "傘指数、情報なし"))
        #expect(!view.accessibilityText.contains { $0.isNumber })
    }

    @Test("実際に0%の予報は欠測と区別して表示する")
    func knownZeroUmbrellaProbability() {
        let view = UmbrellaIndexView(probability: 0)

        #expect(view.valueText == "0")
        #expect(view.accessibilityText.contains("0"))
        #expect(view.accessibilityText.contains(String(localized: "不要でしょう")))
        #expect(!view.accessibilityText.contains(String(localized: "情報なし")))
    }

    @Test("降水確率が欠けている洗濯指数は採点・外干し推奨をしない")
    func missingLaundryProbability() {
        let view = LaundryIndexView(humidity: 50, windSpeed: 3, precipProbability: nil)

        #expect(LaundryIndexView.score(humidity: 50, windSpeed: 3, precipProbability: nil) == nil)
        #expect(view.valueText == "—")
        #expect(view.accessibilityText == String(localized: "洗濯指数、情報なし"))
        #expect(!view.accessibilityText.contains { $0.isNumber })
    }

    @Test("降水確率がある洗濯指数は既存の採点と上下限を維持する")
    func knownLaundryProbabilityKeepsExistingScores() {
        #expect(LaundryIndexView.score(humidity: 50, windSpeed: 3, precipProbability: 0) == 100)
        #expect(LaundryIndexView.score(humidity: 50, windSpeed: 3, precipProbability: 50) == 56)
        #expect(LaundryIndexView.score(humidity: 100, windSpeed: 0, precipProbability: 100) == 0)

        let view = LaundryIndexView(humidity: 50, windSpeed: 3, precipProbability: 0)
        #expect(view.valueText == "100")
        #expect(view.accessibilityText.contains(String(localized: "よく乾きます")))
        #expect(!view.accessibilityText.contains(String(localized: "情報なし")))
    }
}
