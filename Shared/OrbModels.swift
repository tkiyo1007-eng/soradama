import Foundation
import Observation

/// 空玉が生まれた季節。同じ晴れでも季節ごとに玉の質感が変わる。
/// 日付から決まるので、過去に記録した玉にもさかのぼって反映される。
enum Season: String, Codable, CaseIterable {
    case spring, summer, autumn, winter

    var label: String {
        switch self {
        case .spring: return "春"
        case .summer: return "夏"
        case .autumn: return "秋"
        case .winter: return "冬"
        }
    }

    /// その季節の空を一言で表したもの(ずかん用)
    var skyName: String {
        switch self {
        case .spring: return "霞の空"
        case .summer: return "入道雲の空"
        case .autumn: return "高く澄んだ空"
        case .winter: return "凛と冴えた空"
        }
    }

    static func of(month: Int) -> Season {
        switch month {
        case 3...5:   return .spring
        case 6...8:   return .summer
        case 9...11:  return .autumn
        default:      return .winter
        }
    }
}

/// 空玉が生まれた時間帯。同じ天気でも朝焼け・夕暮れ・夜で表情が変わる。
enum TimeOfDay: String, Codable, CaseIterable {
    case dawn, day, dusk, night

    var label: String {
        switch self {
        case .dawn:  return "朝焼け"
        case .day:   return "昼"
        case .dusk:  return "夕暮れ"
        case .night: return "夜"
        }
    }

    /// 日の出・日の入りの前後1時間をマジックアワーとして朝焼け/夕暮れに割り当てる
    /// (空の背景グラデーションと同じ考え方)
    static func at(_ date: Date, sunrise: Date?, sunset: Date?, isDay: Bool) -> TimeOfDay {
        let magicHour: TimeInterval = 3600
        if let sunrise, abs(date.timeIntervalSince(sunrise)) <= magicHour { return .dawn }
        if let sunset, abs(date.timeIntervalSince(sunset)) <= magicHour { return .dusk }
        return isDay ? .day : .night
    }
}

/// 空玉ずかんの1マスにあたる「空模様」。天気と時間帯の組み合わせで決まる。
struct SkyVariant: Hashable, Identifiable {
    let kind: WeatherKind
    let timeOfDay: TimeOfDay

    var id: String { "\(kind.rawValue)-\(timeOfDay.rawValue)" }

    /// ずかんに並べる16マス(天気8種 × 昼夜)。
    /// 朝焼け・夕暮れの玉は「マジックアワー」として別枠で扱う。
    static let zukanEntries: [SkyVariant] = TimeOfDay.allCases
        .filter { $0 == .day || $0 == .night }
        .flatMap { time in WeatherKind.allCases.map { SkyVariant(kind: $0, timeOfDay: time) } }

    var label: String {
        timeOfDay == .day ? kind.label : "夜の\(kind.label)"
    }
}

/// 1日ぶんの空が結晶化した「空玉」。
/// その日の代表的な天気・気温・湿度から玉の見た目が決まる。
struct DailyOrb: Codable, Identifiable, Equatable {
    /// ローカル日付キー("2026-07-20")。1日1玉。
    let dateKey: String
    let kind: WeatherKind
    let tempMax: Double
    let tempMin: Double
    let humidity: Double
    let precipProbability: Double?
    let placeName: String
    /// 節目の日(雷雨・連続記録の区切り・図鑑コンプリート)は、
    /// 玉が多面体クリスタルとして表示される特別版になる。
    /// 既存保存データに存在しないフィールドなので、デコード時のために既定値を持たせる。
    var isMilestone: Bool = false
    /// 玉が記録された時間帯。1.4.0 で追加したため、それ以前のデータは「昼」として扱う。
    var timeOfDay: TimeOfDay = .day

    var id: String { dateKey }

    var date: Date? { Self.keyFormatter.date(from: dateKey) }

    /// 玉が生まれた季節。日付から決まるので過去のデータにもさかのぼって効く。
    var season: Season {
        guard let date else { return .spring }
        return Season.of(month: Calendar.current.component(.month, from: date))
    }

    static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    static func key(for date: Date) -> String {
        // static formatter は初期化時の TZ を持ち続けるため、旅行等で
        // 端末の TZ が変わっても追随するよう毎回設定し直す
        keyFormatter.timeZone = .current
        return keyFormatter.string(from: date)
    }
}

/// 決定的な擬似乱数(フレーム間・プロセス間で同じ並びを得るため)
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let value = (state >> 33) & 0x7FFFFFFF
        return Double(value) / Double(0x7FFFFFFF)
    }
}

/// `String.hashValue` はプロセス起動ごとにシードが変わり安定しないため
/// (ハッシュフラッディング対策)、「同じ日は同じ模様・同じセリフ」という
/// 空玉の設計を満たすには使えない。アプリの再起動をまたいでも同じ値になる
/// FNV-1a による安定したハッシュを代わりに使う。
func stableSeed(for string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return hash
}

/// 今日の玉を記録した結果。獲得演出の出し分けに使う。
struct OrbRecordResult: Equatable {
    /// 今日はじめての記録か(上書き更新なら false)
    let isFirstToday: Bool
    /// 今日を含む連続日数
    let streak: Int
    /// 今日の玉がクリスタル(節目)か
    let isMilestone: Bool
    /// この記録で図鑑に新しい種類が加わったか
    let isNewKind: Bool
}

/// 空玉のローカル保存。1年でも365件程度なので UserDefaults の JSON で十分。
/// アプリ本体の UserDefaults に加えて App Group にも書き込み、
/// ウィジェットからも今日の玉を表示できるようにする。
@Observable
final class OrbStore {
    static let shared = OrbStore()

    private static let storageKey = "soradama.dailyOrbs"
    private(set) var orbs: [String: DailyOrb]

    private static var stores: [UserDefaults] {
        var result: [UserDefaults] = [.standard]
        if let shared = UserDefaults(suiteName: SharedStore.appGroupID) {
            result.append(shared)
        }
        return result
    }

    private init() {
        // 既存ユーザーのデータはアプリ側の UserDefaults にだけあるため、
        // 両方のストアを読んでマージする(ウィジェット側では App Group のみにある)
        var merged: [String: DailyOrb] = [:]
        for store in Self.stores.reversed() {
            if let data = store.data(forKey: Self.storageKey),
               let decoded = try? JSONDecoder().decode([String: DailyOrb].self, from: data) {
                merged.merge(decoded) { _, new in new }
            }
        }
        orbs = merged
    }

    /// 連続記録日数がこの節目に達したとき、その日の玉がクリスタルになる。
    private static let milestoneStreaks: Set<Int> = [7, 14, 30, 50, 100, 200, 365]

    /// 今日の玉を記録(同じ日は最新の取得内容で上書き)。
    /// 現在地(先頭ページ)の取得成功時に呼ばれる。
    @discardableResult
    func recordToday(from bundle: WeatherBundle, placeName: String) -> OrbRecordResult {
        let key = DailyOrb.key(for: Date())
        let isFirstToday = orbs[key] == nil
        let today = bundle.days.first
        let kind = today?.kind ?? bundle.kind

        let alreadyHasKind = orbs.values.contains { $0.kind == kind }
        let otherKindsCollected = Set(orbs.values.map(\.kind)).subtracting([kind]).count
        let completesZukan = !alreadyHasKind && otherKindsCollected == WeatherKind.allCases.count - 1
        let streakIncludingToday = consecutiveDays(before: Date()) + 1
        let isMilestone = kind == .thunderstorm
            || Self.milestoneStreaks.contains(streakIncludingToday)
            || completesZukan

        let orb = DailyOrb(
            dateKey: key,
            kind: kind,
            tempMax: today?.tempMax ?? bundle.temperature,
            tempMin: today?.tempMin ?? bundle.temperature,
            humidity: bundle.humidity,
            precipProbability: today?.precipitationProbability,
            placeName: placeName,
            isMilestone: isMilestone,
            timeOfDay: TimeOfDay.at(
                Date(),
                sunrise: bundle.sunrise,
                sunset: bundle.sunset,
                isDay: bundle.isDay
            )
        )
        orbs[key] = orb
        persist()
        return OrbRecordResult(
            isFirstToday: isFirstToday,
            streak: streakIncludingToday,
            isMilestone: isMilestone,
            isNewKind: !alreadyHasKind
        )
    }

    func orb(for date: Date) -> DailyOrb? {
        orbs[DailyOrb.key(for: date)]
    }

    /// 今日から遡って何日連続で玉があるか。
    var streak: Int {
        orbs[DailyOrb.key(for: Date())] != nil ? consecutiveDays(before: Date()) + 1 : 0
    }

    /// 指定日の"前日"から遡って、何日連続で玉があるか(指定日自体は数えない)。
    private func consecutiveDays(before date: Date) -> Int {
        var count = 0
        let calendar = Calendar.current
        guard var cursor = calendar.date(byAdding: .day, value: -1, to: date) else { return 0 }
        while orbs[DailyOrb.key(for: cursor)] != nil {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// 指定した月に含まれる玉の数。
    func count(inMonthOf date: Date) -> Int {
        orbs(inMonthOf: date).count
    }

    /// 指定した月の玉を日付順に返す。
    func orbs(inMonthOf date: Date) -> [DailyOrb] {
        let calendar = Calendar.current
        return orbs.values
            .filter {
                guard let orbDate = $0.date else { return false }
                return calendar.isDate(orbDate, equalTo: date, toGranularity: .month)
            }
            .sorted { $0.dateKey < $1.dateKey }
    }

    /// これまでに集めた「天気 × 時間帯」の組み合わせ。空玉ずかんのマスに対応する。
    var collectedSkies: Set<SkyVariant> {
        Set(orbs.values.map { SkyVariant(kind: $0.kind, timeOfDay: $0.timeOfDay) })
    }

    /// これまでに玉を記録した季節。
    var collectedSeasons: Set<Season> {
        Set(orbs.values.map(\.season))
    }

    /// その組み合わせを最初に記録した玉(ずかんの詳細表示用)。
    func firstOrb(of variant: SkyVariant) -> DailyOrb? {
        orbs.values
            .filter { $0.kind == variant.kind && $0.timeOfDay == variant.timeOfDay }
            .min { $0.dateKey < $1.dateKey }
    }

    /// その組み合わせを何個持っているか。
    func count(of variant: SkyVariant) -> Int {
        orbs.values.filter { $0.kind == variant.kind && $0.timeOfDay == variant.timeOfDay }.count
    }

    /// 指定した月の振り返り。玉が1つも無い月は nil。
    func summary(forMonthOf date: Date) -> MonthSummary? {
        let monthOrbs = orbs(inMonthOf: date)
        guard !monthOrbs.isEmpty else { return nil }

        var counts: [WeatherKind: Int] = [:]
        for orb in monthOrbs { counts[orb.kind, default: 0] += 1 }

        return MonthSummary(
            month: date,
            orbCount: monthOrbs.count,
            // 「晴れ」は晴れ時々くもりも含めた体感ベースで数える
            sunnyDays: monthOrbs.filter { $0.kind == .clear || $0.kind == .partlyCloudy }.count,
            rainyDays: monthOrbs.filter { $0.kind == .rain || $0.kind == .drizzle || $0.kind == .thunderstorm }.count,
            hottest: monthOrbs.max { $0.tempMax < $1.tempMax },
            coldest: monthOrbs.min { $0.tempMin < $1.tempMin },
            milestoneCount: monthOrbs.filter(\.isMilestone).count,
            kindCounts: counts
        )
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(orbs) {
            for store in Self.stores {
                store.set(data, forKey: Self.storageKey)
            }
        }
    }

}

/// ひと月ぶんの空の振り返り。共有カードの中身になる。
struct MonthSummary {
    let month: Date
    let orbCount: Int
    let sunnyDays: Int
    let rainyDays: Int
    let hottest: DailyOrb?
    let coldest: DailyOrb?
    let milestoneCount: Int
    let kindCounts: [WeatherKind: Int]

    /// その月をひとことで言い表す見出し。
    var headline: String {
        guard orbCount > 0 else { return "空を集めはじめました" }
        let sunnyRatio = Double(sunnyDays) / Double(orbCount)
        let rainyRatio = Double(rainyDays) / Double(orbCount)
        if sunnyRatio >= 0.6 { return "よく晴れたひと月でした" }
        if rainyRatio >= 0.5 { return "雨の記憶が多いひと月でした" }
        if milestoneCount > 0 { return "特別な空に出会えたひと月でした" }
        return "いろんな空があったひと月でした"
    }
}
