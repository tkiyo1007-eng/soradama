import Testing
import Foundation
@testable import AuroraWeather

/// 2026年の季節演出は、端末ローカルのグレゴリオ暦で、ハロウィンは10月1日〜31日、
/// クリスマスは12月1日〜25日だけ有効。期間後に自動で戻り、他の年には開催しないことを固定する。
struct SeasonalEventTests {
    private func calendar(_ identifier: String, kind: Calendar.Identifier = .gregorian) -> Calendar {
        var calendar = Calendar(identifier: kind)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    /// 指定タイムゾーンでの壁時計の時刻を Date にする。
    private func date(_ text: String, in identifier: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: identifier)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    @Test("9月30日と10月1日の境界", arguments: ["Asia/Tokyo", "America/Los_Angeles", "UTC"])
    func startBoundary(zone: String) {
        let calendar = calendar(zone)
        #expect(SeasonalEvent.active(at: date("2026-09-30 23:59:59", in: zone), calendar: calendar) == nil)
        #expect(SeasonalEvent.active(at: date("2026-10-01 00:00:00", in: zone), calendar: calendar) == .halloween2026)
    }

    @Test("10月31日と11月1日の境界", arguments: ["Asia/Tokyo", "America/Los_Angeles", "UTC"])
    func endBoundary(zone: String) {
        let calendar = calendar(zone)
        #expect(SeasonalEvent.active(at: date("2026-10-31 23:59:59", in: zone), calendar: calendar) == .halloween2026)
        #expect(SeasonalEvent.active(at: date("2026-11-01 00:00:00", in: zone), calendar: calendar) == nil)
    }

    @Test("年の指定があり、他の年の10月には開催しない")
    func otherYearsAreInactive() {
        let calendar = calendar("Asia/Tokyo")
        for year in [2025, 2027, 2030] {
            #expect(SeasonalEvent.active(at: date("\(year)-10-15 12:00:00", in: "Asia/Tokyo"), calendar: calendar) == nil)
        }
        #expect(SeasonalEvent.active(at: date("2026-10-15 12:00:00", in: "Asia/Tokyo"), calendar: calendar) == .halloween2026)
    }

    @Test("同じ瞬間でも端末のタイムゾーンの日付で判定する")
    func timeZoneBoundary() {
        // 東京の10月1日0:30 = UTCの9月30日15:30
        let start = date("2026-10-01 00:30:00", in: "Asia/Tokyo")
        #expect(SeasonalEvent.active(at: start, calendar: calendar("Asia/Tokyo")) == .halloween2026)
        #expect(SeasonalEvent.active(at: start, calendar: calendar("UTC")) == nil)
        #expect(SeasonalEvent.active(at: start, calendar: calendar("America/Los_Angeles")) == nil)

        // UTCの11月1日2:00 = ロサンゼルスの10月31日19:00
        let end = date("2026-11-01 02:00:00", in: "UTC")
        #expect(SeasonalEvent.active(at: end, calendar: calendar("UTC")) == nil)
        #expect(SeasonalEvent.active(at: end, calendar: calendar("Asia/Tokyo")) == nil)
        #expect(SeasonalEvent.active(at: end, calendar: calendar("America/Los_Angeles")) == .halloween2026)
    }

    @Test("和暦・仏暦の端末でもグレゴリオ暦の日付で判定する")
    func nonGregorianDeviceCalendar() {
        for kind in [Calendar.Identifier.japanese, .buddhist] {
            let calendar = calendar("Asia/Tokyo", kind: kind)
            #expect(SeasonalEvent.active(at: date("2026-10-15 12:00:00", in: "Asia/Tokyo"), calendar: calendar) == .halloween2026)
            #expect(SeasonalEvent.active(at: date("2026-11-01 00:00:00", in: "Asia/Tokyo"), calendar: calendar) == nil)
            #expect(SeasonalEvent.dayKey(for: date("2026-10-15 12:00:00", in: "Asia/Tokyo"), calendar: calendar) == "2026-10-15")
        }
    }

    @Test("飾りは開催中の今日の玉だけ。ずかんの見本や過去の記録には付けない")
    func onlyTodaysOrbIsDecorated() {
        let calendar = calendar("Asia/Tokyo")
        let now = date("2026-10-20 09:00:00", in: "Asia/Tokyo")
        #expect(SeasonalEvent.decoratesOrb(dateKey: "2026-10-20", at: now, calendar: calendar))
        // 空玉ずかんの秋の見本は2000年10月15日のキーを使う
        #expect(!SeasonalEvent.decoratesOrb(dateKey: "2000-10-15", at: now, calendar: calendar))
        // 同じ期間中でも別の日の記録は対象外
        #expect(!SeasonalEvent.decoratesOrb(dateKey: "2026-10-05", at: now, calendar: calendar))
        #expect(!SeasonalEvent.decoratesOrb(dateKey: "2025-10-20", at: now, calendar: calendar))

        // 期間後は10月の記録も今日の記録も通常表示に戻る
        let after = date("2026-11-01 00:00:00", in: "Asia/Tokyo")
        #expect(!SeasonalEvent.decoratesOrb(dateKey: "2026-10-31", at: after, calendar: calendar))
        #expect(!SeasonalEvent.decoratesOrb(dateKey: "2026-11-01", at: after, calendar: calendar))
    }

    @Test("日付キーは空玉の保存キーと同じ形式")
    func dayKeyMatchesStoredOrbKey() {
        let now = Date()
        #expect(SeasonalEvent.dayKey(for: now) == DailyOrb.key(for: now))
        let context = SeasonalContext.live(now: now)
        #expect(context.todayKey == DailyOrb.key(for: now))
    }

    @Test("画面用の状態は既定で開催なし")
    func defaultContextIsInactive() {
        let orb = DailyOrb(
            dateKey: DailyOrb.key(for: Date()),
            kind: .clear, tempMax: 20, tempMin: 10, humidity: 50,
            precipProbability: nil, placeName: ""
        )
        #expect(!SeasonalContext.none.decorates(orb))
        #expect(!SeasonalContext.none.isHalloween)

        let calendar = calendar("Asia/Tokyo")
        let during = SeasonalContext.live(now: date("2026-10-10 08:00:00", in: "Asia/Tokyo"), calendar: calendar)
        #expect(during.isHalloween)
        #expect(during.todayKey == "2026-10-10")
        let after = SeasonalContext.live(now: date("2026-11-01 08:00:00", in: "Asia/Tokyo"), calendar: calendar)
        #expect(!after.isHalloween)
    }

    @Test("詳細を開いたまま日付が変わると、共有画像の再生成キーが変わる")
    func shareImageKeyFollowsDayChange() {
        let calendar = calendar("Asia/Tokyo")
        func orb(_ key: String) -> DailyOrb {
            DailyOrb(dateKey: key, kind: .clear, tempMax: 20, tempMin: 10, humidity: 50,
                     precipProbability: nil, placeName: "")
        }
        func context(_ text: String) -> SeasonalContext {
            .live(now: date(text, in: "Asia/Tokyo"), calendar: calendar)
        }

        // 10月31日の玉: 当日は飾り付き、11月1日0時に期間が終わると飾りなし
        let lastDay = orb("2026-10-31")
        let before = OrbShareImageKey(orb: lastDay, seasonal: context("2026-10-31 23:59:59"))
        let after = OrbShareImageKey(orb: lastDay, seasonal: context("2026-11-01 00:00:00"))
        #expect(before.decoration == .halloween2026)
        #expect(after.decoration == nil)
        #expect(before != after)

        // 期間中の通常の日付変更: 前日の玉は「今日の玉」でなくなり飾りが外れる
        let fifth = orb("2026-10-05")
        #expect(OrbShareImageKey(orb: fifth, seasonal: context("2026-10-05 23:59:00"))
                != OrbShareImageKey(orb: fifth, seasonal: context("2026-10-06 00:00:00")))

        // 状態が同じなら作り直さない。別の日の玉へ切り替えたときは作り直す
        let now = context("2026-10-20 09:00:00")
        #expect(OrbShareImageKey(orb: orb("2026-10-20"), seasonal: now)
                == OrbShareImageKey(orb: orb("2026-10-20"), seasonal: now))
        #expect(OrbShareImageKey(orb: orb("2026-10-20"), seasonal: now)
                != OrbShareImageKey(orb: orb("2026-10-19"), seasonal: now))
    }

    // MARK: - クリスマス

    @Test("11月30日と12月1日の境界", arguments: ["Asia/Tokyo", "America/Los_Angeles", "UTC"])
    func christmasStartBoundary(zone: String) {
        let calendar = calendar(zone)
        #expect(SeasonalEvent.active(at: date("2026-11-30 23:59:59", in: zone), calendar: calendar) == nil)
        #expect(SeasonalEvent.active(at: date("2026-12-01 00:00:00", in: zone), calendar: calendar) == .christmas2026)
    }

    @Test("12月25日と12月26日の境界", arguments: ["Asia/Tokyo", "America/Los_Angeles", "UTC"])
    func christmasEndBoundary(zone: String) {
        let calendar = calendar(zone)
        #expect(SeasonalEvent.active(at: date("2026-12-25 23:59:59", in: zone), calendar: calendar) == .christmas2026)
        #expect(SeasonalEvent.active(at: date("2026-12-26 00:00:00", in: zone), calendar: calendar) == nil)
        #expect(SeasonalEvent.active(at: date("2026-12-31 12:00:00", in: zone), calendar: calendar) == nil)
    }

    @Test("ハロウィンとクリスマスの間の11月は開催なし。他の年の12月も開催しない")
    func christmasOnlyIn2026() {
        let calendar = calendar("Asia/Tokyo")
        #expect(SeasonalEvent.active(at: date("2026-11-15 12:00:00", in: "Asia/Tokyo"), calendar: calendar) == nil)
        for year in [2025, 2027] {
            #expect(SeasonalEvent.active(at: date("\(year)-12-10 12:00:00", in: "Asia/Tokyo"), calendar: calendar) == nil)
        }
        #expect(SeasonalEvent.active(at: date("2027-01-01 00:00:00", in: "Asia/Tokyo"), calendar: calendar) == nil)
    }

    @Test("和暦・仏暦の端末でもクリスマスはグレゴリオ暦の日付で判定する")
    func christmasNonGregorianDeviceCalendar() {
        for kind in [Calendar.Identifier.japanese, .buddhist] {
            let calendar = calendar("Asia/Tokyo", kind: kind)
            #expect(SeasonalEvent.active(at: date("2026-12-24 20:00:00", in: "Asia/Tokyo"), calendar: calendar) == .christmas2026)
            #expect(SeasonalEvent.active(at: date("2026-12-26 00:00:00", in: "Asia/Tokyo"), calendar: calendar) == nil)
        }
    }

    @Test("クリスマスの飾りも開催中の今日の玉だけ")
    func christmasDecoratesOnlyToday() {
        let calendar = calendar("Asia/Tokyo")
        func orb(_ key: String) -> DailyOrb {
            DailyOrb(dateKey: key, kind: .snow, tempMax: 5, tempMin: -1, humidity: 70,
                     precipProbability: nil, placeName: "")
        }
        let during = SeasonalContext.live(now: date("2026-12-24 09:00:00", in: "Asia/Tokyo"), calendar: calendar)
        #expect(during.isChristmas)
        #expect(!during.isHalloween)
        #expect(during.decoration(for: orb("2026-12-24")) == .christmas2026)
        #expect(during.decoration(for: orb("2026-12-23")) == nil)
        #expect(during.decoration(for: orb("2000-12-15")) == nil)

        let after = SeasonalContext.live(now: date("2026-12-26 00:00:00", in: "Asia/Tokyo"), calendar: calendar)
        #expect(!after.isChristmas)
        #expect(after.decoration(for: orb("2026-12-26")) == nil)

        // 12月25日の詳細を開いたまま26日になると、共有画像を作り直す
        let lastDay = orb("2026-12-25")
        let before = OrbShareImageKey(
            orb: lastDay,
            seasonal: .live(now: date("2026-12-25 23:59:59", in: "Asia/Tokyo"), calendar: calendar)
        )
        let next = OrbShareImageKey(
            orb: lastDay,
            seasonal: .live(now: date("2026-12-26 00:00:00", in: "Asia/Tokyo"), calendar: calendar)
        )
        #expect(before.decoration == .christmas2026)
        #expect(next.decoration == nil)
        #expect(before != next)
    }
}
