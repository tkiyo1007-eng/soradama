import Testing
import Foundation
@testable import AuroraWeather

/// 暦まわりの計算を、実際に起きた天文現象と照らして検証する。
///
/// ここが壊れると「今日は白露です」「満月の夜です」が静かに間違うだけで、
/// 画面を見ても気づけない。過去に実際、節気が1日ずれ・満月が1日早い状態で
/// リリース直前まで気づかなかったため、テストで固定する。
struct AstronomyTests {

    private static let utc = TimeZone(identifier: "UTC")!
    private static let jst = TimeZone(identifier: "Asia/Tokyo")!

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0,
                             in zone: TimeZone = utc) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: - 太陽黄経

    @Test("春分の瞬間、太陽黄経はほぼ0度になる")
    func solarLongitudeAtEquinox() {
        // 2025年の春分: 3月20日 09:01 UTC
        let longitude = Astronomy.solarLongitude(Self.date(2025, 3, 20, 9, 1))
        // 0度をまたぐので、0付近か360付近ならよい
        let distance = min(longitude, 360 - longitude)
        #expect(distance < 0.1, "春分の太陽黄経が0度から\(distance)度ずれている")
    }

    @Test("夏至の瞬間、太陽黄経はほぼ90度になる")
    func solarLongitudeAtSolstice() {
        // 2025年の夏至: 6月21日 02:42 UTC
        let longitude = Astronomy.solarLongitude(Self.date(2025, 6, 21, 2, 42))
        #expect(abs(longitude - 90) < 0.1, "夏至の太陽黄経が90度から\(abs(longitude - 90))度ずれている")
    }

    // MARK: - 月相

    @Test("皆既日食の瞬間は新月なので、月と太陽の黄経差はほぼ0度")
    func moonPhaseAtSolarEclipse() {
        // 2024年4月8日の皆既日食: 18:21 UTC(食の最大)
        let angle = Astronomy.moonPhaseAngle(Self.date(2024, 4, 8, 18, 21))
        let distance = min(angle, 360 - angle)
        #expect(distance < 1.0, "日食時の黄経差が0度から\(distance)度ずれている")
    }

    @Test("皆既月食の瞬間は満月なので、黄経差はほぼ180度")
    func moonPhaseAtLunarEclipse() {
        // 2025年9月7日の皆既月食: 18:09 UTC(食の最大)
        let angle = Astronomy.moonPhaseAngle(Self.date(2025, 9, 7, 18, 9))
        #expect(abs(angle - 180) < 1.0, "月食時の黄経差が180度から\(abs(angle - 180))度ずれている")
    }

    @Test("満ち具合は新月で0、満月で1に近づく")
    func illuminationRange() {
        let newMoon = MoonPhase.illumination(at: Self.date(2024, 4, 8, 18, 21))
        let fullMoon = MoonPhase.illumination(at: Self.date(2025, 9, 7, 18, 9))
        #expect(newMoon < 0.01)
        #expect(fullMoon > 0.99)
    }

    // MARK: - 二十四節気

    @Test("2026年の立秋は8月7日（固定値では8月8日と誤っていた）")
    func risshu2026() {
        let term = SolarTerm.on(Self.date(2026, 8, 7, 12, 0, in: Self.jst), timeZone: Self.jst)
        #expect(term == .risshu)
        // 前日・翌日は節気ではない
        #expect(SolarTerm.on(Self.date(2026, 8, 6, 12, 0, in: Self.jst), timeZone: Self.jst) == nil)
        #expect(SolarTerm.on(Self.date(2026, 8, 8, 12, 0, in: Self.jst), timeZone: Self.jst) == nil)
    }

    @Test("2026年の白露は9月7日（固定値では9月8日と誤っていた）")
    func hakuro2026() {
        #expect(SolarTerm.on(Self.date(2026, 9, 7, 12, 0, in: Self.jst), timeZone: Self.jst) == .hakuro)
        #expect(SolarTerm.on(Self.date(2026, 9, 8, 12, 0, in: Self.jst), timeZone: Self.jst) == nil)
    }

    @Test("春分・夏至・秋分・冬至が正しい日に出る")
    func majorTerms() {
        #expect(SolarTerm.on(Self.date(2026, 3, 20, 12, 0, in: Self.jst), timeZone: Self.jst) == .shunbun)
        #expect(SolarTerm.on(Self.date(2026, 6, 21, 12, 0, in: Self.jst), timeZone: Self.jst) == .geshi)
        #expect(SolarTerm.on(Self.date(2026, 9, 23, 12, 0, in: Self.jst), timeZone: Self.jst) == .shubun)
        #expect(SolarTerm.on(Self.date(2026, 12, 22, 12, 0, in: Self.jst), timeZone: Self.jst) == .toji)
    }

    @Test("一年を通して節気はちょうど24個",
          arguments: [2025, 2026, 2027])
    func exactlyTwentyFourTermsPerYear(year: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.jst
        var found: [SolarTerm] = []

        for month in 1...12 {
            for day in 1...31 {
                guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
                      calendar.component(.month, from: date) == month else { continue }
                if let term = SolarTerm.on(date, timeZone: Self.jst) { found.append(term) }
            }
        }
        #expect(found.count == 24, "\(year)年の節気が\(found.count)個しか見つからない")
        // 同じ節気が二度出ないこと
        #expect(Set(found).count == 24, "\(year)年に重複した節気がある")
    }
}
