import Testing
import Foundation
@testable import AuroraWeather

/// 天気キャッシュ(WeatherBundle)の保存形式。
/// UV 指数の欠測を nil で持てるようにした後も、1.8.5 以前が保存した「必ず数値」のキャッシュを
/// そのまま読めること、欠測が保存を経て 0 に化けないことを固定する。
struct WeatherBundleCodingTests {
    private func bundle(uvIndex: Double?) -> WeatherBundle {
        let date = Date(timeIntervalSince1970: 1_900_000)
        return WeatherBundle(
            fetchedAt: date,
            timeZoneID: "UTC",
            temperature: 20,
            apparentTemperature: 20,
            kind: .clear,
            isDay: true,
            humidity: 50,
            windSpeed: 3,
            windDirection: 180,
            pressure: 1013,
            uvIndex: uvIndex,
            visibility: 10_000,
            sunrise: date,
            sunset: date.addingTimeInterval(43_200),
            hours: [],
            days: []
        )
    }

    @Test("欠測のUVは保存しても 0 に化けず、キーごと省かれる")
    func missingUVRoundTrips() throws {
        let data = try JSONEncoder().encode(bundle(uvIndex: nil))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["uvIndex"] == nil)
        let decoded = try JSONDecoder().decode(WeatherBundle.self, from: data)
        #expect(decoded.uvIndex == nil)
    }

    @Test("数値のUVは 0 も含めて往復で保持する")
    func numericUVRoundTrips() throws {
        for value in [0.0, 2.5, 11.0] {
            let data = try JSONEncoder().encode(bundle(uvIndex: value))
            #expect(try JSONDecoder().decode(WeatherBundle.self, from: data).uvIndex == value)
        }
    }

    @Test("1.8.5 以前のキャッシュ(uvIndex が必ず数値)はそのまま読める")
    func legacyCacheDecodes() throws {
        var json = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(bundle(uvIndex: 3))) as? [String: Any]
        )
        // 旧版が書いた JSON と同じ形(uvIndex キーが数値で存在する)であることを確かめてから読む
        #expect(json["uvIndex"] as? Double == 3)
        // 旧版は欠測を 0 で保存していた。それも 0 として読める(キャッシュの期限 6 時間で入れ替わる)
        json["uvIndex"] = 0
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(try JSONDecoder().decode(WeatherBundle.self, from: data).uvIndex == 0)
    }
}
