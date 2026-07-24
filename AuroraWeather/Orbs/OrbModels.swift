import Foundation

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

    var id: String { dateKey }

    var date: Date? { Self.keyFormatter.date(from: dateKey) }

    static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    static func key(for date: Date) -> String {
        keyFormatter.string(from: date)
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

/// 空玉のローカル保存。1年でも365件程度なので UserDefaults の JSON で十分。
final class OrbStore {
    static let shared = OrbStore()

    private static let storageKey = "soradama.dailyOrbs"
    private(set) var orbs: [String: DailyOrb]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: DailyOrb].self, from: data) {
            orbs = decoded
        } else {
            orbs = [:]
        }
    }

    /// 連続記録日数がこの節目に達したとき、その日の玉がクリスタルになる。
    private static let milestoneStreaks: Set<Int> = [7, 14, 30, 50, 100, 200, 365]

    /// 今日の玉を記録(同じ日は最新の取得内容で上書き)。
    /// 現在地(先頭ページ)の取得成功時に呼ばれる。
    func recordToday(from bundle: WeatherBundle, placeName: String) {
        let key = DailyOrb.key(for: Date())
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
            isMilestone: isMilestone
        )
        orbs[key] = orb
        persist()
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
        let calendar = Calendar.current
        return orbs.values.filter {
            guard let orbDate = $0.date else { return false }
            return calendar.isDate(orbDate, equalTo: date, toGranularity: .month)
        }.count
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(orbs) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
