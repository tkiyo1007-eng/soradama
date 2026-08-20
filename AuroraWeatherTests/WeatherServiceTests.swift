import Testing
import Foundation
@testable import AuroraWeather

/// 天気APIのレスポンス解析まわり。
///
/// 日本国内では気象庁(JMA)モデルで予報を取っているが、
/// **JMA は降水確率・UV指数・視程を返さない**（実データで確認済み）。
/// そこでグローバルモデルへ並行リクエストを投げ、時刻をキーにして補完している。
///
/// ここが壊れると傘指数と洗濯指数が丸ごと消える。しかも「取得はできている」ので
/// エラーにはならず、ただ数値が出なくなるだけという気づきにくい壊れ方をする。
struct WeatherServiceTests {

    // MARK: - 補完(merge)

    /// 時刻が完全に一致する、いちばん素直なケース。
    @Test("JMAに無い降水確率がグローバルモデルから補われる")
    func mergeFillsMissingPrecipitation() {
        let times: [Double] = [1_000, 4_600, 8_200]
        let primary = Self.forecast(hourlyTimes: times, precipitation: nil)
        let supplement = Self.supplement(times: times, precipitation: [10, 50, 90])

        let merged = WeatherService.merge(primary: primary, supplement: supplement)

        #expect(merged.hourly.precipitationProbability?.compactMap { $0 } == [10, 50, 90])
        // 補完で上書きしてはいけないもの(JMA 側の予報)がそのまま残ること
        #expect(merged.hourly.temperature == primary.hourly.temperature)
        #expect(merged.hourly.weatherCode == primary.hourly.weatherCode)
    }

    /// 補完側の時刻が1時間ずれている場合。
    /// 添字で合わせていると、ここで全部1時間ずれた値が入ってしまう。
    @Test("時刻がずれている値は取り込まない(添字ではなく時刻で引く)")
    func mergeMatchesByTimeNotIndex() {
        let primaryTimes: [Double] = [1_000, 4_600, 8_200]
        // 補完側は 3_600 秒(1時間)後ろにずれている
        let supplementTimes: [Double] = [4_600, 8_200, 11_800]
        let primary = Self.forecast(hourlyTimes: primaryTimes, precipitation: nil)
        let supplement = Self.supplement(times: supplementTimes, precipitation: [50, 90, 20])

        let merged = WeatherService.merge(primary: primary, supplement: supplement)
        let values = merged.hourly.precipitationProbability

        // 先頭(1_000)は補完側に無いので nil のまま。ここに 50 が入ったらずれている
        #expect(values?[0] == nil, "時刻が無い枠に、ずれた値が入り込んでいる")
        #expect(values?[1] == 50)
        #expect(values?[2] == 90)
    }

    /// グローバルモデルへのリクエストが失敗しても、予報自体は表示できないといけない。
    @Test("補完が取れなくても本体の予報は残る")
    func mergeSurvivesMissingSupplement() {
        let times: [Double] = [1_000, 4_600]
        let primary = Self.forecast(hourlyTimes: times, precipitation: nil)

        let merged = WeatherService.merge(primary: primary, supplement: nil)

        #expect(merged.hourly.time == times)
        #expect(merged.hourly.temperature.count == times.count)
        #expect(merged.hourly.precipitationProbability == nil)
    }

    /// 補完側のほうが配列が短いことがある(提供期間の違い)。
    /// 添字アクセスしていると範囲外でクラッシュする。
    @Test("補完側が短くてもクラッシュしない")
    func mergeHandlesShorterSupplement() {
        let primaryTimes: [Double] = [1_000, 4_600, 8_200, 11_800]
        let primary = Self.forecast(hourlyTimes: primaryTimes, precipitation: nil)
        let supplement = Self.supplement(times: [1_000, 4_600], precipitation: [30, 40])

        let merged = WeatherService.merge(primary: primary, supplement: supplement)
        let values = merged.hourly.precipitationProbability

        #expect(values?.count == primaryTimes.count)
        #expect(values?[0] == 30)
        #expect(values?[3] == nil)
    }

    // MARK: - JMA モデルを使う範囲

    /// 日本近域だけ JMA モデルを指定する。範囲を間違えると、
    /// 海外で「日本の気象庁モデル」を要求してしまい予報が壊れる。
    @Test("日本近域だけ気象庁モデルを使う")
    func jmaCoverage() {
        #expect(WeatherService.usesJMAModel(latitude: 35.68, longitude: 139.76))   // 東京
        #expect(WeatherService.usesJMAModel(latitude: 26.21, longitude: 127.68))   // 那覇
        #expect(WeatherService.usesJMAModel(latitude: 43.06, longitude: 141.35))   // 札幌
        #expect(!WeatherService.usesJMAModel(latitude: 51.50, longitude: -0.12))   // ロンドン
        #expect(!WeatherService.usesJMAModel(latitude: 37.77, longitude: -122.41)) // サンフランシスコ
        // 緯度だけ日本と重なる地点で誤判定しないこと
        #expect(!WeatherService.usesJMAModel(latitude: 37.98, longitude: 23.72))   // アテネ
    }

    // MARK: - 補助

    private static func forecast(hourlyTimes: [Double], precipitation: [Double?]?) -> ForecastResponse {
        let json = """
        {
          "latitude": 35.68, "longitude": 139.76, "timezone": "Asia/Tokyo",
          "current": {
            "time": \(hourlyTimes[0]), "temperature_2m": 20, "relative_humidity_2m": 50,
            "apparent_temperature": 20, "is_day": 1, "precipitation": 0, "weather_code": 0,
            "wind_speed_10m": 3, "wind_direction_10m": 180, "pressure_msl": 1013
          },
          "hourly": {
            "time": \(hourlyTimes),
            "temperature_2m": \(hourlyTimes.map { _ in 20.0 }),
            "weather_code": \(hourlyTimes.map { _ in 0 })
          },
          "daily": {
            "time": [\(hourlyTimes[0])],
            "weather_code": [0], "temperature_2m_max": [25], "temperature_2m_min": [15],
            "sunrise": [\(hourlyTimes[0])], "sunset": [\(hourlyTimes[0] + 43_200)]
          }
        }
        """
        return try! JSONDecoder().decode(ForecastResponse.self, from: Data(json.utf8))
    }

    private static func supplement(times: [Double], precipitation: [Double?]) -> WeatherService.SupplementResponse {
        let parts: [String] = precipitation.map { value in
            guard let value else { return "null" }
            return String(value)
        }
        let values = parts.joined(separator: ",")
        let json = """
        {
          "hourly": { "time": \(times), "precipitation_probability": [\(values)] },
          "daily": { "time": [\(times[0])], "precipitation_probability_max": [50] }
        }
        """
        return try! JSONDecoder().decode(WeatherService.SupplementResponse.self, from: Data(json.utf8))
    }
}
