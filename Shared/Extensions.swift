import Foundation
import SwiftUI

/// `DateFormatter` の生成は重い。毎時カード25件・10日間予報・チャート軸で
/// 再描画のたびに作り直していたため、書式とタイムゾーンの組でキャッシュする。
private enum DateFormatterCache {
    private static let lock = NSLock()
    private static var cache: [String: DateFormatter] = [:]

    /// - Parameter template: true なら書式を「テンプレート」として扱い、
    ///   並び順や12/24時間表記を端末のロケールに合わせて組み立て直す。
    ///   日本語で "15時" になるものが、英語では "3 PM" になる。
    static func formatter(_ format: String, _ timeZone: TimeZone, template: Bool = false) -> DateFormatter {
        // ロケールもキーに含める。設定アプリで言語を変えて戻ってきたとき、
        // 古い言語の書式を使い続けてしまわないように。
        let key = "\(template ? "T:" : "")\(format)|\(timeZone.identifier)|\(Locale.current.identifier)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = timeZone
        if template {
            formatter.setLocalizedDateFormatFromTemplate(format)
        } else {
            formatter.dateFormat = format
        }
        cache[key] = formatter
        return formatter
    }
}

extension Date {
    /// 指定タイムゾーンでの時刻表示(日本語なら "15時"、英語なら "3 PM")
    func hourLabel(in timeZone: TimeZone) -> String {
        DateFormatterCache.formatter("j", timeZone, template: true).string(from: self)
    }

    /// 分まで含む短い時刻(日本語なら "5:03"、英語なら "5:03 AM")
    func timeLabel(in timeZone: TimeZone) -> String {
        DateFormatterCache.formatter("jmm", timeZone, template: true).string(from: self)
    }

    /// 曜日("月" / "Mon")
    func weekdayLabel(in timeZone: TimeZone) -> String {
        DateFormatterCache.formatter("E", timeZone, template: true).string(from: self)
    }

    func isSameDay(as other: Date, in timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.isDate(self, inSameDayAs: other)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension Color {
    /// 2色を線形補間する(amount 0 で自分自身、1 で other)。
    /// 時刻に応じた空の色を連続的に変化させるために使う。
    func blended(with other: Color, amount: Double) -> Color {
        let t = amount.clamped(to: 0...1)
        let a = UIColor(self).rgba
        let b = UIColor(other).rgba
        return Color(
            red: a.r + (b.r - a.r) * t,
            green: a.g + (b.g - a.g) * t,
            blue: a.b + (b.b - a.b) * t
        )
    }
}

private extension UIColor {
    var rgba: (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
}
