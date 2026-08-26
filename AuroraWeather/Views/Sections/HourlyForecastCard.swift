import SwiftUI

/// 24 時間分の毎時予報を横スクロールで表示するカード
struct HourlyForecastCard: View {
    let weather: WeatherBundle
    let degrees: (Double) -> String

    /// 「今」と表示してよいコマ。オフラインでキャッシュを見ているときは
    /// 先頭が過去の時刻になっているので、配列の先頭かどうかで判断してはいけない。
    private var currentHourIndex: Int? {
        Self.currentHourIndex(in: weather.hours, now: Date(), calendar: .current)
    }

    static func currentHourIndex(in hours: [HourForecast], now: Date, calendar: Calendar) -> Int? {
        hours.firstIndex {
            calendar.isDate($0.date, equalTo: now, toGranularity: .hour)
        }
    }

    static func accessibilityTimeLabel(
        isCurrentHour: Bool,
        date: Date,
        timeZone: TimeZone
    ) -> String {
        isCurrentHour ? String(localized: "現在") : date.hourLabel(in: timeZone)
    }

    var body: some View {
        GlassCard(title: "時間ごとの予報", systemImage: "clock") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(Array(weather.hours.enumerated()), id: \.element.id) { index, hour in
                        let isNow = index == currentHourIndex
                        VStack(spacing: 10) {
                            // 三項演算子の型は String に落ちるため、Text 任せでは翻訳されない。
                            // ここだけ明示的に localized を通す。
                            Text(isNow ? String(localized: "今") : hour.date.hourLabel(in: weather.timeZone))
                                .font(.footnote.weight(isNow ? .bold : .medium))
                                .foregroundStyle(.white.opacity(isNow ? 1 : 0.75))

                            VStack(spacing: 3) {
                                WeatherIconView(kind: hour.kind, isDay: hour.isDay)
                                    .frame(width: 26, height: 26)

                                if let probability = hour.precipitationProbability, probability >= 20 {
                                    Text("\(Int(probability))%")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color(red: 0.55, green: 0.85, blue: 1.0))
                                } else {
                                    Text(" ")
                                        .font(.caption2)
                                }
                            }

                            Text(degrees(hour.temperature))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityText(isCurrentHour: isNow, hour: hour))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func accessibilityText(isCurrentHour: Bool, hour: HourForecast) -> String {
        // 連結で組み立てると翻訳対象として抽出されないため、補間を含むキーにまとめる
        let timeLabel = Self.accessibilityTimeLabel(
            isCurrentHour: isCurrentHour,
            date: hour.date,
            timeZone: weather.timeZone
        )
        let base = String(localized: "\(timeLabel)、\(hour.kind.label)、\(degrees(hour.temperature))")
        guard let probability = hour.precipitationProbability, probability >= 20 else { return base }
        return String(localized: "\(base)、降水確率\(Int(probability))パーセント")
    }
}
