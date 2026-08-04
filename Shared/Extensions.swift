import Foundation
import SwiftUI

/// `DateFormatter` の生成は重い。毎時カード25件・10日間予報・チャート軸で
/// 再描画のたびに作り直していたため、書式とタイムゾーンの組でキャッシュする。
private enum DateFormatterCache {
    private static let lock = NSLock()
    private static var cache: [String: DateFormatter] = [:]

    static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let key = "\(format)|\(timeZone.identifier)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        cache[key] = formatter
        return formatter
    }
}

extension Date {
    /// 指定タイムゾーンでの時刻表示("15時" 形式)
    func hourLabel(in timeZone: TimeZone) -> String {
        DateFormatterCache.formatter("H時", timeZone).string(from: self)
    }

    /// "5:03" のような短い時刻
    func timeLabel(in timeZone: TimeZone) -> String {
        DateFormatterCache.formatter("H:mm", timeZone).string(from: self)
    }

    /// 曜日("月" など)
    func weekdayLabel(in timeZone: TimeZone) -> String {
        DateFormatterCache.formatter("E", timeZone).string(from: self)
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
