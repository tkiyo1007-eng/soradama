import Foundation

// MARK: - Open-Meteo API レスポンス(timeformat=unixtime で取得)

struct ForecastResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let timezone: String
    let current: Current
    let hourly: Hourly
    let daily: Daily

    struct Current: Decodable {
        let time: Double
        let temperature: Double
        let humidity: Double
        let apparentTemperature: Double
        let isDay: Int
        let precipitation: Double
        let weatherCode: Int
        let windSpeed: Double
        let windDirection: Double
        let pressure: Double
        let uvIndex: Double?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case humidity = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case isDay = "is_day"
            case precipitation
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
            case windDirection = "wind_direction_10m"
            case pressure = "pressure_msl"
            case uvIndex = "uv_index"
        }
    }

    struct Hourly: Decodable {
        let time: [Double]
        let temperature: [Double]
        let weatherCode: [Int]
        let precipitationProbability: [Double?]?
        let uvIndex: [Double?]?
        let visibility: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case precipitationProbability = "precipitation_probability"
            case uvIndex = "uv_index"
            case visibility
        }
    }

    struct Daily: Decodable {
        let time: [Double]
        let weatherCode: [Int]
        let temperatureMax: [Double]
        let temperatureMin: [Double]
        let sunrise: [Double]
        let sunset: [Double]
        let precipitationProbabilityMax: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
            case sunrise
            case sunset
            case precipitationProbabilityMax = "precipitation_probability_max"
        }
    }
}

struct GeocodingResponse: Decodable {
    let results: [GeoPlace]?
}

struct GeoPlace: Decodable, Identifiable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?
}

// MARK: - アプリ内ドメインモデル

struct HourForecast: Identifiable, Codable {
    let id: Int
    let date: Date
    let temperature: Double
    let kind: WeatherKind
    let isDay: Bool
    let precipitationProbability: Double?
}

struct DayForecast: Identifiable, Codable {
    let id: Int
    let date: Date
    let kind: WeatherKind
    let tempMax: Double
    let tempMin: Double
    let precipitationProbability: Double?
}

/// オフラインキャッシュのため Codable。タイムゾーンは識別子文字列で保持する。
struct WeatherBundle: Codable {
    let fetchedAt: Date
    let timeZoneID: String

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    let temperature: Double
    let apparentTemperature: Double
    let kind: WeatherKind
    let isDay: Bool
    let humidity: Double
    let windSpeed: Double
    let windDirection: Double
    let pressure: Double
    let uvIndex: Double
    let visibility: Double?

    let sunrise: Date
    let sunset: Date

    let hours: [HourForecast]
    let days: [DayForecast]

    /// キャッシュが日をまたいでも「昨日」を今日として扱わない。
    func dayForecast(for date: Date = .now) -> DayForecast? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// 現在時刻から表示可能な時間別予報。時刻境界のずれを30分だけ許容する。
    func upcomingHours(from date: Date = .now) -> [HourForecast] {
        let cutoff = date.addingTimeInterval(-30 * 60)
        return hours.filter { $0.date >= cutoff }
    }

    /// 現地タイムゾーンの今日以降だけを返し、日跨ぎキャッシュの昨日を除く。
    func upcomingDays(from date: Date = .now) -> [DayForecast] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfToday = calendar.startOfDay(for: date)
        return days.filter { $0.date >= startOfToday }
    }

    var todayMax: Double { dayForecast()?.tempMax ?? temperature }


    /// 直近 N 時間以内の最大降水確率。傘指数・洗濯指数のように「今から数時間」を
    /// 判断材料にしたい場面で使う。`days.first` の「今日1日の最大値」だと、
    /// 深夜の雨予報のせいで日中ずっと高い数値のままになるなど実感とズレるため。
    func maxPrecipitationProbability(withinHours limit: Int) -> Double? {
        let relevant = upcomingHours().prefix(limit).compactMap(\.precipitationProbability)
        return relevant.max()
    }
    var todayMin: Double { dayForecast()?.tempMin ?? temperature }
}

// MARK: - 保存地点・設定

struct SavedPlace: Codable, Identifiable, Equatable, Hashable {
    /// 現在地は測位のたびに座標の下位桁が揺れるため、座標を ID にすると
    /// 起動ごとに別ページ扱いになりキャッシュが永遠にヒットしない。
    /// 現在地は固定 ID にして「圏外でも前回の現在地データを表示できる」ようにする。
    var id: String { isCurrentLocation ? "current-location" : "\(latitude),\(longitude)" }
    let name: String
    let detail: String
    let latitude: Double
    let longitude: Double
    var isCurrentLocation: Bool = false

    /// 位置情報を許可してもらえなかったときに最初に見せる地点。
    /// 名前は表示にしか使わない(ID は座標から作る)ので、言語に合わせて訳してよい。
    static let fallback = SavedPlace(
        name: String(localized: "東京"),
        detail: String(localized: "日本"),
        latitude: 35.6895,
        longitude: 139.6917
    )
}

/// 表示に使う単位系。気温だけでなく風速・気圧・距離もまとめて切り替える。
/// 華氏を選ぶのは主にヤード・ポンド圏のユーザーなので、
/// 気温だけ華氏で風速が m/s のままだと表示がちぐはぐになる。
enum UnitSystem: String, Codable, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }
    var label: String {
        self == .celsius
            ? String(localized: "メートル法 (°C・m/s)")
            : String(localized: "ヤード・ポンド法 (°F・mph)")
    }
    var suffix: String { self == .celsius ? "°C" : "°F" }

    /// 初回だけ端末地域に合う単位を選ぶ。英国は気温に摂氏を使うため
    /// `.uk` をメートル法側にし、明示的に米国式の地域だけ華氏にする。
    static func defaultSystem(for measurementSystem: Locale.MeasurementSystem) -> UnitSystem {
        measurementSystem == .us ? .fahrenheit : .celsius
    }

    static var localeDefault: UnitSystem {
        defaultSystem(for: Locale.current.measurementSystem)
    }

    func convert(_ celsius: Double) -> Double {
        self == .celsius ? celsius : celsius * 9 / 5 + 32
    }

    // MARK: 風速

    /// m/s を表示用の値に変換する(華氏側は mph)
    func windSpeed(_ metersPerSecond: Double) -> Double {
        self == .celsius ? metersPerSecond : metersPerSecond * 2.236936
    }
    var windSpeedUnit: String { self == .celsius ? "m/s" : "mph" }

    // MARK: 気圧

    /// hPa を表示用の値に変換する(華氏側は inHg)
    func pressure(_ hectopascals: Double) -> Double {
        self == .celsius ? hectopascals : hectopascals * 0.02952998
    }
    var pressureUnit: String { self == .celsius ? "hPa" : "inHg" }
    /// inHg は小数第2位まで見せないと変化が分からない
    var pressureFractionDigits: Int { self == .celsius ? 0 : 2 }

    // MARK: 距離(視程)

    /// メートルを表示用の値に変換する(華氏側はマイル)
    func distance(_ meters: Double) -> Double {
        self == .celsius ? meters / 1000 : meters / 1609.344
    }
    var distanceUnit: String { self == .celsius ? "km" : "mi" }
}
