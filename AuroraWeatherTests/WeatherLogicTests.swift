import Testing
import Foundation
@testable import AuroraWeather

/// 天気まわりの純粋ロジック。
/// ここに並んでいるのは、いずれも過去に実際やらかして修正した箇所で、
/// 画面を見ただけでは間違いに気づきにくいものばかり。
struct WeatherLogicTests {

    // MARK: - 傘指数・洗濯指数が見る時間の窓

    /// 「今日1日の最大降水確率」を見ていたせいで、深夜の雨予報のせいで
    /// 日中ずっと高い数値のままになり「あてにならない」と言われた。
    /// 直近N時間の最大値を返すことを固定する。
    @Test("直近N時間の最大降水確率だけを見る")
    func maxPrecipitationWithinHours() {
        let now = Date()
        var hours: [HourForecast] = []
        for index in 0..<24 {
            // 3時間後に30%、20時間後(=深夜)に90%
            var probability: Double = 0
            if index == 3 { probability = 30 }
            if index == 20 { probability = 90 }
            hours.append(HourForecast(
                id: index,
                date: now.addingTimeInterval(Double(index) * 3600),
                temperature: 20,
                kind: .clear,
                isDay: true,
                precipitationProbability: probability
            ))
        }
        let bundle = Self.bundle(hours: hours)

        #expect(bundle.maxPrecipitationProbability(withinHours: 10) == 30,
                "直近10時間なのに、20時間後の90%を拾ってしまっている")
        #expect(bundle.maxPrecipitationProbability(withinHours: 24) == 90)
    }

    @Test("降水確率が1件も無ければ nil")
    func maxPrecipitationWithNoData() {
        let now = Date()
        var hours: [HourForecast] = []
        for index in 0..<5 {
            hours.append(HourForecast(id: index, date: now.addingTimeInterval(Double(index) * 3600),
                                      temperature: 20, kind: .clear, isDay: true,
                                      precipitationProbability: nil))
        }
        #expect(Self.bundle(hours: hours).maxPrecipitationProbability(withinHours: 5) == nil)
    }

    // MARK: - 一言と傘指数の食い違い

    /// 「☀️ 晴れ／空にひとつも雲がありません」の真下に「傘指数82% 傘が必須です」が
    /// 並ぶ画面を実機で見つけた。どちらの数字も正しいのに、壊れて見える。
    /// 晴れていても雨が近いときは、一言のほうを雨寄りに切り替える。
    @Test("晴れでも数時間後に雨なら一言が雨寄りになる")
    func voiceWarnsAboutComingRain() {
        let now = Date()
        var hours: [HourForecast] = []
        for index in 0..<24 {
            hours.append(HourForecast(
                id: index,
                date: now.addingTimeInterval(Double(index) * 3600),
                temperature: 23,
                kind: .clear,
                isDay: true,
                precipitationProbability: index >= 6 ? 82 : 10
            ))
        }
        let sunny = Self.bundle(hours: hours)
        let line = OrbVoice.line(for: sunny)
        #expect(!line.contains("雲がありません"), "傘が必須なのに『雲がありません』と言っている")
    }

    /// 逆に、本当に一日晴れているときは晴れの一言のままであること。
    @Test("雨の気配がなければ晴れの一言のまま")
    func voiceStaysSunnyWhenDry() {
        let now = Date()
        var hours: [HourForecast] = []
        for index in 0..<24 {
            hours.append(HourForecast(
                id: index, date: now.addingTimeInterval(Double(index) * 3600),
                temperature: 23, kind: .clear, isDay: true,
                precipitationProbability: 5
            ))
        }
        let line = OrbVoice.line(for: Self.bundle(hours: hours))
        #expect(!line.contains("傘"), "雨の気配がないのに傘の話をしている")
    }

    // MARK: - 単位換算

    @Test("摂氏・華氏の換算")
    func temperatureConversion() {
        #expect(UnitSystem.celsius.convert(25) == 25)
        #expect(abs(UnitSystem.fahrenheit.convert(0) - 32) < 0.001)
        #expect(abs(UnitSystem.fahrenheit.convert(100) - 212) < 0.001)
    }

    /// 華氏を選んだのに風速が m/s のままだったので、まとめて切り替わるようにした。
    @Test("華氏を選ぶと風速・気圧・距離もヤードポンド系になる")
    func unitSystemCoversAllMeasurements() {
        let imperial = UnitSystem.fahrenheit
        #expect(abs(imperial.windSpeed(10) - 22.369) < 0.01)   // m/s → mph
        #expect(abs(imperial.pressure(1013) - 29.91) < 0.01)   // hPa → inHg
        #expect(abs(imperial.distance(1609.344) - 1.0) < 0.001) // m → mile
        #expect(imperial.windSpeedUnit == "mph")
        #expect(imperial.pressureUnit == "inHg")
        #expect(imperial.distanceUnit == "mi")

        let metric = UnitSystem.celsius
        #expect(metric.windSpeed(10) == 10)
        #expect(metric.pressure(1013) == 1013)
        #expect(metric.distance(1000) == 1)
    }

    // MARK: - 風向

    /// 負の角度や NaN が来ると配列外アクセスでクラッシュしていた。
    @Test("風向は負値・360超・NaN でもクラッシュしない")
    func windDirectionIsSafe() {
        #expect(WindCompassView.directionName(0) == "北")
        #expect(WindCompassView.directionName(90) == "東")
        #expect(WindCompassView.directionName(180) == "南")
        #expect(WindCompassView.directionName(270) == "西")
        // 異常値でも落ちずに何かを返す
        #expect(WindCompassView.directionName(-90) == "西")
        #expect(WindCompassView.directionName(450) == "東")
        _ = WindCompassView.directionName(.nan)
        _ = WindCompassView.directionName(.infinity)
    }

    // MARK: - WMO コードの対応

    @Test("WMOコードが天気の種類に正しく対応する")
    func weatherKindFromWMOCode() {
        #expect(WeatherKind(wmoCode: 0) == .clear)
        #expect(WeatherKind(wmoCode: 1) == .clear)        // 「おおむね晴れ」は晴れ扱い
        #expect(WeatherKind(wmoCode: 2) == .partlyCloudy)
        #expect(WeatherKind(wmoCode: 3) == .cloudy)
        #expect(WeatherKind(wmoCode: 45) == .fog)
        #expect(WeatherKind(wmoCode: 61) == .rain)
        #expect(WeatherKind(wmoCode: 71) == .snow)
        #expect(WeatherKind(wmoCode: 95) == .thunderstorm)
    }

    // MARK: - 現在地の扱い

    /// 現在地は測位のたびに座標の下位桁が変わる。座標を ID にしていたため
    /// 起動ごとに別ページ扱いになり、キャッシュが永遠にヒットしなかった。
    @Test("現在地は座標が揺れても同じIDになる")
    func currentLocationHasStableID() {
        let first = SavedPlace(name: "現在地", detail: "", latitude: 35.6812, longitude: 139.7671, isCurrentLocation: true)
        let second = SavedPlace(name: "現在地", detail: "", latitude: 35.6813, longitude: 139.7669, isCurrentLocation: true)
        #expect(first.id == second.id, "現在地の座標が少し動いただけで別IDになっている")

        // 検索した地点は座標ごとに別IDのままでよい
        let tokyo = SavedPlace(name: "東京", detail: "", latitude: 35.68, longitude: 139.76)
        let osaka = SavedPlace(name: "大阪", detail: "", latitude: 34.69, longitude: 135.50)
        #expect(tokyo.id != osaka.id)
    }

    // MARK: - 補助

    private static func bundle(hours: [HourForecast]) -> WeatherBundle {
        WeatherBundle(
            fetchedAt: Date(), timeZoneID: "Asia/Tokyo",
            temperature: 20, apparentTemperature: 20, kind: .clear, isDay: true,
            humidity: 50, windSpeed: 3, windDirection: 180, pressure: 1013,
            uvIndex: 3, visibility: 10000,
            sunrise: Date(), sunset: Date(),
            hours: hours, days: []
        )
    }
}

/// 空玉まわり。日付キーとシードは「同じ日は必ず同じ見た目」を支えている。
struct OrbLogicTests {

    /// `String.hashValue` はプロセスごとに変わるため、再起動で模様が変わってしまった。
    @Test("シードは同じ文字列なら常に同じ値になる")
    func stableSeedIsDeterministic() {
        #expect(stableSeed(for: "2026-08-08") == stableSeed(for: "2026-08-08"))
        #expect(stableSeed(for: "2026-08-08") != stableSeed(for: "2026-08-09"))
    }

    @Test("同じシードなら乱数の並びも同じ")
    func seededRandomIsReproducible() {
        var a = SeededRandom(seed: 12345)
        var b = SeededRandom(seed: 12345)
        for _ in 0..<10 { #expect(a.next() == b.next()) }
        // 0..<1 の範囲に収まる
        var c = SeededRandom(seed: 999)
        for _ in 0..<100 {
            let value = c.next()
            #expect(value >= 0 && value < 1)
        }
    }

    @Test("季節は月から決まる")
    func seasonFromMonth() {
        #expect(Season.of(month: 4) == .spring)
        #expect(Season.of(month: 7) == .summer)
        #expect(Season.of(month: 10) == .autumn)
        #expect(Season.of(month: 1) == .winter)
        #expect(Season.of(month: 12) == .winter)
    }

    @Test("空玉ずかんは天気8種 × 昼夜 の16マス")
    func zukanHasSixteenEntries() {
        #expect(SkyVariant.zukanEntries.count == 16)
        #expect(Set(SkyVariant.zukanEntries).count == 16, "ずかんに重複したマスがある")
        // 朝焼け・夕暮れはマジックアワー枠なので、ずかんの16マスには含めない
        #expect(!SkyVariant.zukanEntries.contains { $0.timeOfDay == .dawn || $0.timeOfDay == .dusk })
    }

    /// 日の出・日の入りの前後1時間はマジックアワーとして扱う。
    @Test("時間帯の判定")
    func timeOfDayClassification() {
        let sunrise = Date(timeIntervalSince1970: 1_800_000_000)
        let sunset = sunrise.addingTimeInterval(12 * 3600)

        // 日の出30分後 → 朝焼け
        #expect(TimeOfDay.at(sunrise.addingTimeInterval(1800), sunrise: sunrise, sunset: sunset, isDay: true) == .dawn)
        // 日の入り30分前 → 夕暮れ
        #expect(TimeOfDay.at(sunset.addingTimeInterval(-1800), sunrise: sunrise, sunset: sunset, isDay: true) == .dusk)
        // 真昼 → 昼
        #expect(TimeOfDay.at(sunrise.addingTimeInterval(6 * 3600), sunrise: sunrise, sunset: sunset, isDay: true) == .day)
        // 真夜中 → 夜
        #expect(TimeOfDay.at(sunset.addingTimeInterval(4 * 3600), sunrise: sunrise, sunset: sunset, isDay: false) == .night)
    }
}
