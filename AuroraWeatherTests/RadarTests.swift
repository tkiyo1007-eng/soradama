import Testing
import Foundation
@testable import AuroraWeather

/// 雨雲レーダー(気象庁ナウキャスト)まわり。
///
/// RainViewer から移す際に実測で分かった気象庁側の癖を固定しておく。
/// 特にズームレベルの扱いは、間違えても「200 が返るが中身は透明」という
/// 静かな壊れ方をするため、画面を見ても気づけない。
struct RadarTests {

    // MARK: - 提供範囲

    /// 気象庁のレーダーは日本周辺しか覆っていない。
    /// 範囲外の地点で真っ暗な地図を見せないための判定。
    @Test("日本国内は提供範囲に入る")
    func japanIsCovered() {
        #expect(RadarService.isCovered(latitude: 35.68, longitude: 139.76))  // 東京
        #expect(RadarService.isCovered(latitude: 26.21, longitude: 127.68))  // 那覇
        #expect(RadarService.isCovered(latitude: 43.06, longitude: 141.35))  // 札幌
    }

    /// パリは緯度48.85で日本と重なるため、経度も見ないと通ってしまう。
    @Test("海外は提供範囲から外れる")
    func overseasIsNotCovered() {
        #expect(!RadarService.isCovered(latitude: 48.85, longitude: 2.35))    // パリ(緯度は日本と同帯)
        #expect(!RadarService.isCovered(latitude: 40.71, longitude: -74.00))  // ニューヨーク
        #expect(!RadarService.isCovered(latitude: -33.87, longitude: 151.21)) // シドニー(経度は日本と同帯)
        #expect(!RadarService.isCovered(latitude: 1.35, longitude: 103.82))   // シンガポール
    }

    // MARK: - 時刻の解釈

    /// 気象庁の時刻文字列はタイムゾーン表記を持たない JST。
    /// UTC として読むと9時間ずれ、コマの時刻表示が全部おかしくなる。
    @Test("時刻文字列はJSTとして読む")
    func timeStringIsParsedAsJST() throws {
        let date = try #require(RadarService.parse("20260810205500"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        #expect(parts.year == 2026)
        #expect(parts.month == 8)
        #expect(parts.day == 10)
        #expect(parts.hour == 20)
        #expect(parts.minute == 55)
    }

    @Test("壊れた時刻文字列は nil になる")
    func invalidTimeStringIsNil() {
        #expect(RadarService.parse("") == nil)
        #expect(RadarService.parse("2026-08-10") == nil)
    }

    // MARK: - フレーム

    @Test("実況と予測はフラグで区別できる")
    func frameKind() {
        let past = RadarFrame(baseTime: "20260810205000", validTime: "20260810205000", isForecast: false)
        let future = RadarFrame(baseTime: "20260810205000", validTime: "20260810215000", isForecast: true)
        #expect(!past.isForecast)
        #expect(future.isForecast)
        #expect(past.id != future.id, "基準時刻が同じでも表示時刻が違えば別のコマ")
        #expect(future.date > past.date)
    }
}
