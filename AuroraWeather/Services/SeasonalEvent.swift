import Foundation

/// 期間限定の季節演出。開催年を固定し、翌年以降に自動で繰り返さない。
/// 保存済みの空玉や天気の意味には触れず、表示だけを切り替える。
enum SeasonalEvent: String, Equatable {
    /// 2026年10月1日〜10月31日(端末ローカル日付)。11月1日に通常へ戻る。
    case halloween2026
    /// 2026年12月1日〜12月25日(端末ローカル日付)。12月26日に通常へ戻る。
    case christmas2026

    /// 渡された時刻・Calendarのタイムゾーンで、グレゴリオ暦の日付として判定する。
    /// 和暦・仏暦の端末でも同じ期間になるよう、暦法はグレゴリオ暦に揃える。
    static func active(at date: Date, calendar: Calendar = .current) -> SeasonalEvent? {
        let components = gregorian(matching: calendar).dateComponents([.year, .month, .day], from: date)
        guard components.year == 2026, let day = components.day else { return nil }
        switch components.month {
        case 10:
            return .halloween2026
        case 12 where day <= 25:
            return .christmas2026
        default:
            return nil
        }
    }

    /// 季節の飾りを付けてよい空玉か。開催中の「今日」に記録された玉だけを対象にし、
    /// ずかんの見本(2000年の日付)や期間中の過去の記録を期間の獲得物として扱わない。
    static func decoratesOrb(dateKey: String, at date: Date, calendar: Calendar = .current) -> Bool {
        guard active(at: date, calendar: calendar) != nil else { return false }
        return dateKey == dayKey(for: date, calendar: calendar)
    }

    /// `DailyOrb.key(for:)` と同じ yyyy-MM-dd 形式の日付キー。
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = gregorian(matching: calendar).dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func gregorian(matching calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }
}

/// 画面が参照する季節演出の状態。ContentView が現在時刻から作り、環境値で配る。
/// 既定値は「開催なし」なので、プレビューや壁紙の書き出しには演出が混ざらない。
struct SeasonalContext: Equatable {
    let event: SeasonalEvent?
    /// 飾りを付ける空玉の日付キー(今日)。
    let todayKey: String

    static let none = SeasonalContext(event: nil, todayKey: "")

    static func live(now: Date, calendar: Calendar = .current) -> SeasonalContext {
        SeasonalContext(
            event: SeasonalEvent.active(at: now, calendar: calendar),
            todayKey: SeasonalEvent.dayKey(for: now, calendar: calendar)
        )
    }

    var isHalloween: Bool { event == .halloween2026 }
    var isChristmas: Bool { event == .christmas2026 }

    func decorates(_ orb: DailyOrb) -> Bool {
        decoration(for: orb) != nil
    }

    /// その玉に付ける季節の飾り。開催中の今日の玉だけ、開催中の行事を返す。
    func decoration(for orb: DailyOrb) -> SeasonalEvent? {
        orb.dateKey == todayKey ? event : nil
    }
}
