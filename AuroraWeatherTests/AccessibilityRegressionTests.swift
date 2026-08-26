import Testing
import Foundation
@testable import AuroraWeather

/// ロケールや選択単位によってだけ現れる、見落としやすいUI回帰を固定する。
struct AccessibilityRegressionTests {

    @Test("日曜始まりの月表示は日曜列に1日を置く")
    func sundayFirstMonthLayout() throws {
        let calendar = Self.gregorianCalendar(firstWeekday: 1)
        let august2026 = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))

        let days = OrbCalendarLayout.monthDays(for: august2026, calendar: calendar)

        #expect(days.firstIndex(where: { $0 != nil }) == 6)
        #expect(days.compactMap { $0 }.count == 31)
    }

    @Test("月曜始まりの月表示は月曜を先頭列として空欄を計算する")
    func mondayFirstMonthLayout() throws {
        let calendar = Self.gregorianCalendar(firstWeekday: 2)
        let august2026 = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))

        let days = OrbCalendarLayout.monthDays(for: august2026, calendar: calendar)

        #expect(days.firstIndex(where: { $0 != nil }) == 5)
        #expect(days.compactMap { $0 }.count == 31)
    }

    @Test("毎時予報の現在読み上げは実際の現在時刻のコマに付く")
    func hourlyCurrentAccessibilityFollowsCurrentHourIndex() throws {
        let calendar = Self.gregorianCalendar(firstWeekday: 1)
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 26, hour: 10, minute: 30
        )))
        let hours = [-1, 0, 1].enumerated().map { pair in
            let (index, offset) = pair
            return HourForecast(
                id: index,
                date: now.addingTimeInterval(TimeInterval(offset * 3_600)),
                temperature: 20,
                kind: .clear,
                isDay: true,
                precipitationProbability: nil
            )
        }

        let currentIndex = HourlyForecastCard.currentHourIndex(
            in: hours,
            now: now,
            calendar: calendar
        )
        let labels = hours.indices.map { index in
            HourlyForecastCard.accessibilityTimeLabel(
                isCurrentHour: index == currentIndex,
                date: hours[index].date,
                timeZone: calendar.timeZone
            )
        }

        #expect(currentIndex == 1, "先頭が過去のキャッシュでも、現在時刻は2件目")
        #expect(labels[0] != String(localized: "現在"))
        #expect(labels[1] == String(localized: "現在"))
    }

    @Test("風速の読み上げは選択した単位系と一致する")
    func windAccessibilityUsesSelectedUnits() {
        let metric = WindCompassView.accessibilityText(
            direction: 0,
            speed: 5,
            units: .celsius
        )
        let imperial = WindCompassView.accessibilityText(
            direction: 0,
            speed: 5,
            units: .fahrenheit
        )

        #expect(metric.contains("5 m/s"))
        #expect(imperial.contains("11 mph"))
        #expect(!imperial.contains("m/s"))
    }

    @Test("レーダーの時刻スライダーは時刻と実況・予測を読み上げる")
    func radarSliderAccessibilityDescribesFrame() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let observedFrame = RadarFrame(
            baseTime: "20260826100000",
            validTime: "20260826100000",
            isForecast: false
        )
        let forecastFrame = RadarFrame(
            baseTime: "20260826100000",
            validTime: "20260826103000",
            isForecast: true
        )

        let observed = RadarSheet.accessibilityValue(for: observedFrame, timeZone: tokyo)
        let forecast = RadarSheet.accessibilityValue(for: forecastFrame, timeZone: tokyo)

        #expect(observed.contains(String(localized: "実況")))
        #expect(forecast.contains(String(localized: "予測")))
        #expect(observed.contains { $0.isNumber })
        #expect(forecast.contains { $0.isNumber })
        #expect(RadarSheet.accessibilityValue(for: nil, timeZone: tokyo).isEmpty)
    }

    private static func gregorianCalendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }
}
