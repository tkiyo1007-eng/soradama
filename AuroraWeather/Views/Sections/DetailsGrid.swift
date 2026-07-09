import SwiftUI

/// 詳細情報のグリッド: 日の出アーク・風向コンパス・UV・湿度・体感温度・気圧・視程
struct DetailsGrid: View {
    let weather: WeatherBundle
    let degrees: (Double) -> String

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            GlassCard(title: "日の出・日の入り", systemImage: "sunrise") {
                SunArcView(sunrise: weather.sunrise, sunset: weather.sunset, now: Date(), timeZone: weather.timeZone)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("日の出 \(weather.sunrise.timeLabel(in: weather.timeZone))、日の入り \(weather.sunset.timeLabel(in: weather.timeZone))")
            GlassCard(title: "風", systemImage: "wind") {
                WindCompassView(direction: weather.windDirection, speed: weather.windSpeed)
            }
            GlassCard(title: "UV指数", systemImage: "sun.max") {
                UVGaugeView(value: weather.uvIndex)
            }
            GlassCard(title: "湿度", systemImage: "humidity") {
                HumidityView(value: weather.humidity)
            }
            GlassCard(title: "体感温度", systemImage: "thermometer.medium") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(degrees(weather.apparentTemperature))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(apparentComment)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            }
            GlassCard(title: "気圧", systemImage: "gauge.with.needle") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Int(weather.pressure.rounded()))")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    + Text(" hPa")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(pressureComment)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            }
        }
        if let visibility = weather.visibility {
            GlassCard(title: "視程", systemImage: "eye") {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", visibility / 1000))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("km")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(visibility >= 10_000 ? "とてもクリアな視界です" : visibility >= 4_000 ? "おおむね良好な視界です" : "視界が悪くなっています")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var apparentComment: String {
        let difference = weather.apparentTemperature - weather.temperature
        if difference >= 2 { return "実際より暖かく感じます" }
        if difference <= -2 { return "実際より寒く感じます" }
        return "実際の気温とほぼ同じ体感です"
    }

    private var pressureComment: String {
        if weather.pressure >= 1020 { return "高気圧・安定した天気" }
        if weather.pressure <= 1005 { return "低気圧・天気の崩れに注意" }
        return "標準的な気圧です"
    }
}

// MARK: - 日の出・日の入りタイムライン

/// 日の出から日の入りまでの経過を横一直線のタイムラインで示す独自デザイン。
/// (Apple 純正「天気」アプリの半円アークとは異なる表現)
struct SunArcView: View {
    let sunrise: Date
    let sunset: Date
    let now: Date
    let timeZone: TimeZone

    private var progress: Double {
        let total = sunset.timeIntervalSince(sunrise)
        guard total > 0 else { return 0 }
        return (now.timeIntervalSince(sunrise) / total).clamped(to: 0...1)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                WeatherIconView(kind: .clear, isDay: true)
                    .frame(width: 22, height: 22)
                Text(progress >= 1 ? "日没しました" : "日中です")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 8)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.72, blue: 0.35), Color(red: 1.0, green: 0.88, blue: 0.55)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(width * progress, 8), height: 8)

                    Circle()
                        .fill(Color(red: 1.0, green: 0.86, blue: 0.5))
                        .frame(width: 16, height: 16)
                        .shadow(color: Color(red: 1.0, green: 0.8, blue: 0.4).opacity(0.8), radius: 6)
                        .offset(x: (width - 16) * progress)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 16)

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("日の出")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(sunrise.timeLabel(in: timeZone))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("日の入り")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(sunset.timeLabel(in: timeZone))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(minHeight: 110)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("日の出 \(sunrise.timeLabel(in: timeZone))、日の入り \(sunset.timeLabel(in: timeZone))")
    }
}

// MARK: - 風向インジケーター

/// 風向を示す矢印バッジ。(Apple 純正「天気」アプリの目盛り付きコンパスとは異なる、
/// バッジ+テキストのシンプルな表現)
struct WindCompassView: View {
    let direction: Double // 風が「吹いてくる」方角(度)
    let speed: Double     // m/s

    /// 16方位の日本語名(VoiceOver 用)
    static func directionName(_ degrees: Double) -> String {
        let names = ["北", "北北東", "北東", "東北東", "東", "東南東", "南東", "南南東",
                     "南", "南南西", "南西", "西南西", "西", "西北西", "北西", "北北西"]
        let index = Int(((degrees + 11.25) / 22.5).rounded(.down)) % 16
        return names[index]
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                Image(systemName: "arrow.up")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(red: 0.55, green: 0.85, blue: 1.0))
                    .rotationEffect(.degrees(direction + 180))
                    .animation(.spring(duration: 1.0), value: direction)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.directionName(direction))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 3) {
                    Text(String(format: "%.0f", speed))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("m/s")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.directionName(direction))の風、秒速\(Int(speed.rounded()))メートル")
    }
}

// MARK: - UV インデックスリング

/// UV 指数を円形リングで示す独自デザイン。
/// (Apple 純正「天気」アプリの横棒ゲージとは異なるリング表現)
struct UVGaugeView: View {
    let value: Double

    private var level: (String, Color) {
        switch value {
        case ..<3:  return ("低い", Color(red: 0.45, green: 0.85, blue: 0.55))
        case 3..<6: return ("中程度", Color(red: 1.0, green: 0.85, blue: 0.40))
        case 6..<8: return ("強い", Color(red: 1.0, green: 0.60, blue: 0.30))
        case 8..<11: return ("非常に強い", Color(red: 0.95, green: 0.35, blue: 0.30))
        default:    return ("極端に強い", Color(red: 0.75, green: 0.40, blue: 0.95))
        }
    }

    private var ringProgress: Double {
        (value / 11).clamped(to: 0...1)
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(level.1, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(level.0)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(level.1)
                Text("UV指数")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
    }
}

// MARK: - 湿度

struct HumidityView: View {
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(Int(value.rounded()))%")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.25))
                        .frame(height: 5)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.45, green: 0.75, blue: 1.0), Color(red: 0.30, green: 0.55, blue: 0.95)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: (value / 100).clamped(to: 0...1) * proxy.size.width, height: 5)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 10)

            Text(value >= 75 ? "蒸し暑く感じられます" : value <= 35 ? "乾燥しています" : "快適な湿度です")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
    }
}
