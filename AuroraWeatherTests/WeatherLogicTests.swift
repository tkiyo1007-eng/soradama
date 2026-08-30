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

    @Test("オフライン予報は過去の時間と昨日を表示対象から除く")
    func cachedForecastsExcludePastPeriods() throws {
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.startOfDay(for: now)
        let hours = [
            HourForecast(id: 0, date: now.addingTimeInterval(-3 * 3600), temperature: 18, kind: .clear, isDay: true, precipitationProbability: 0),
            HourForecast(id: 1, date: now.addingTimeInterval(-10 * 60), temperature: 19, kind: .clear, isDay: true, precipitationProbability: 0),
            HourForecast(id: 2, date: now.addingTimeInterval(3600), temperature: 20, kind: .clear, isDay: true, precipitationProbability: 0),
        ]
        let days = [
            DayForecast(id: 0, date: try #require(calendar.date(byAdding: .day, value: -1, to: today)), kind: .clear, tempMax: 17, tempMin: 9, precipitationProbability: 0),
            DayForecast(id: 1, date: today, kind: .partlyCloudy, tempMax: 21, tempMin: 11, precipitationProbability: 10),
            DayForecast(id: 2, date: try #require(calendar.date(byAdding: .day, value: 1, to: today)), kind: .rain, tempMax: 19, tempMin: 12, precipitationProbability: 70),
        ]
        let bundle = WeatherBundle(
            fetchedAt: now.addingTimeInterval(-3 * 3600),
            timeZoneID: "UTC",
            temperature: 19,
            apparentTemperature: 19,
            kind: .clear,
            isDay: true,
            humidity: 50,
            windSpeed: 3,
            windDirection: 180,
            pressure: 1013,
            uvIndex: 2,
            visibility: 10_000,
            sunrise: today,
            sunset: today.addingTimeInterval(43_200),
            hours: hours,
            days: days
        )

        #expect(bundle.upcomingHours(from: now).map(\.id) == [1, 2])
        #expect(bundle.upcomingDays(from: now).map(\.id) == [1, 2])
        #expect(bundle.dayForecast(for: now)?.id == 1)
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

    @Test("初回の単位は端末の地域に合わせる")
    func localeDefaultUnitSystem() {
        #expect(UnitSystem.defaultSystem(for: .us) == .fahrenheit)
        #expect(UnitSystem.defaultSystem(for: .metric) == .celsius)
        #expect(UnitSystem.defaultSystem(for: .uk) == .celsius)
    }

    // MARK: - 風向

    /// 負の角度や NaN が来ると配列外アクセスでクラッシュしていた。
    @Test("風向は負値・360超・NaN でもクラッシュしない")
    func windDirectionIsSafe() {
        let cardinalDirections = [0.0, 90.0, 180.0, 270.0].map(WindCompassView.directionName)
        let expectedDirections = ["北", "東", "南", "西"].map {
            Bundle.main.localizedString(forKey: $0, value: $0, table: nil)
        }
        #expect(cardinalDirections == expectedDirections,
                "0/90/180/270度が北/東/南/西に対応する")
        #expect(WindCompassView.directionName(360) == WindCompassView.directionName(0))
        #expect(WindCompassView.directionName(-90) == WindCompassView.directionName(270))
        #expect(WindCompassView.directionName(450) == WindCompassView.directionName(90))
        #expect(WindCompassView.directionName(.nan) == WindCompassView.directionName(0))
        #expect(WindCompassView.directionName(.infinity) == WindCompassView.directionName(0))
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

    @Test("旧版の空玉JSONは追加フィールドが無くても読める")
    func legacyDailyOrbJSONUsesDefaults() throws {
        let json = """
        {
          "2026-07-20": {
            "dateKey": "2026-07-20",
            "kind": "clear",
            "tempMax": 31.5,
            "tempMin": 24.0,
            "humidity": 68.0,
            "precipProbability": 10.0,
            "placeName": "東京"
          }
        }
        """

        let decoded = try JSONDecoder().decode(
            [String: DailyOrb].self,
            from: Data(json.utf8)
        )
        let orb = try #require(decoded["2026-07-20"])

        #expect(orb.isMilestone == false)
        #expect(orb.timeOfDay == .day)
        #expect(orb.hemisphere == .northern)
        #expect(orb.kind == .clear)
        #expect(orb.placeName == "東京")
    }

    @Test("現行の空玉は追加フィールドを往復して保持する")
    func currentDailyOrbRoundTripPreservesFields() throws {
        let original = DailyOrb(
            dateKey: "2026-08-26",
            kind: .thunderstorm,
            tempMax: 29.0,
            tempMin: 22.0,
            humidity: 81.0,
            precipProbability: 75.0,
            placeName: "大阪",
            isMilestone: true,
            timeOfDay: .night,
            hemisphere: .southern
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DailyOrb.self, from: data)
        let json = String(decoding: data, as: UTF8.self)

        #expect(decoded == original)
        #expect(decoded.isMilestone)
        #expect(decoded.timeOfDay == .night)
        #expect(decoded.hemisphere == .southern)
        #expect(json.contains("\"hemisphere\":\"southern\""))
        #expect(!json.contains("latitude"), "空玉JSONに正確な緯度は保存しない")
    }

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

    @Test("南半球では季節の視覚表現が北半球の半年後になる")
    func southernHemisphereSeasonsAreReversed() {
        #expect(Season.of(month: 4, hemisphere: .southern) == .autumn)
        #expect(Season.of(month: 7, hemisphere: .southern) == .winter)
        #expect(Season.of(month: 10, hemisphere: .southern) == .spring)
        #expect(Season.of(month: 1, hemisphere: .southern) == .summer)
    }

    @Test("緯度は正確な座標を保存せず半球だけに変換する")
    func latitudeDeterminesHemisphere() {
        #expect(Hemisphere.at(latitude: 35.6762) == .northern)
        #expect(Hemisphere.at(latitude: -33.8688) == .southern)
        #expect(Hemisphere.at(latitude: 0) == .northern)
        #expect(Hemisphere.at(latitude: nil) == .northern)
        #expect(Hemisphere.at(latitude: .nan) == .northern)
        #expect(Hemisphere.at(latitude: 91) == .northern)

        #expect(Season.of(month: 7, latitude: -33.8688) == .winter)
        #expect(Season.of(month: 7, latitude: 35.6762) == .summer)
    }

    @Test("空玉の季節だけを半球で反転し二十四節気と月相は保つ")
    func dailyOrbLocalizesOnlyVisualSeason() {
        let northern = DailyOrb(
            dateKey: "2026-07-20",
            kind: .clear,
            tempMax: 30,
            tempMin: 20,
            humidity: 50,
            precipProbability: nil,
            placeName: "Tokyo",
            timeOfDay: .night,
            hemisphere: .northern
        )
        let southern = DailyOrb(
            dateKey: northern.dateKey,
            kind: northern.kind,
            tempMax: northern.tempMax,
            tempMin: northern.tempMin,
            humidity: northern.humidity,
            precipProbability: northern.precipProbability,
            placeName: "Sydney",
            timeOfDay: northern.timeOfDay,
            hemisphere: .southern
        )

        #expect(northern.season == .summer)
        #expect(southern.season == .winter)
        #expect(northern.solarTerm == southern.solarTerm)
        #expect(northern.moonPhase == southern.moonPhase)
        #expect(northern.moonIllumination == southern.moonIllumination)
    }

    @Test("空玉ずかんは天気8種 × 昼夜 の16マス")
    func zukanHasSixteenEntries() {
        #expect(SkyVariant.zukanEntries.count == 16)
        #expect(Set(SkyVariant.zukanEntries).count == 16, "ずかんに重複したマスがある")
        // 朝焼け・夕暮れはマジックアワー枠なので、ずかんの16マスには含めない
        #expect(!SkyVariant.zukanEntries.contains { $0.timeOfDay == .dawn || $0.timeOfDay == .dusk })

        var collected = Set(SkyVariant.zukanEntries)
        collected.insert(SkyVariant(kind: .clear, timeOfDay: .dawn))
        collected.insert(SkyVariant(kind: .clear, timeOfDay: .dusk))
        #expect(SkyVariant.zukanCollectedCount(in: collected) == 16)
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
