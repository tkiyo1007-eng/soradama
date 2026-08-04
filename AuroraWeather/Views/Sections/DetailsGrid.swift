import SwiftUI

/// 詳細情報の横スクロールカルーセル: 傘指数・体感温度・UV・風・湿度(視程含む)・気圧・日の出アーク
///
/// Apple 純正「天気」アプリの固定2列グリッドとは異なり、横スクロールの
/// カード列として提示する。先頭に純正アプリには無い「傘指数」を独自項目として置き、
/// 項目の組み合わせ自体も純正アプリの詳細グリッドと一致しないようにしている。
struct DetailsGrid: View {
    let weather: WeatherBundle
    let degrees: (Double) -> String
    /// 気温以外(風速・気圧・視程)も同じ単位系で表示するために受け取る
    var units: UnitSystem = .celsius

    /// カード幅・高さは文字サイズ設定に追従させる。
    /// 固定値のままだと、大きな文字設定で説明文が折り返して見切れていた。
    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 176
    @ScaledMetric(relativeTo: .body) private var cardMinHeight: CGFloat = 96

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                GlassCard(title: "傘指数", systemImage: "umbrella") {
                    // 「これから出かけて戻ってくるまで」の目安として、直近10時間の予報を見る
                    // (今日1日の最大値だと、夜の雨予報のせいで日中も高い数値のままになってしまう。
                    //  逆に短すぎると、すぐ先の時間ごとの予報と数値が食い違って見える)
                    UmbrellaIndexView(probability: weather.maxPrecipitationProbability(withinHours: 10))
                }
                .frame(width: cardWidth)

                GlassCard(title: "洗濯指数", systemImage: "tshirt") {
                    // 朝に干して夕方取り込む想定で、直近14時間(日中いっぱい)の予報を見る
                    LaundryIndexView(
                        humidity: weather.humidity,
                        windSpeed: weather.windSpeed,
                        precipProbability: weather.maxPrecipitationProbability(withinHours: 14)
                    )
                }
                .frame(width: cardWidth)

                GlassCard(title: "体感温度", systemImage: "thermometer.medium") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(degrees(weather.apparentTemperature))
                            .font(.system(.title, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                        Text(apparentComment)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: cardMinHeight, alignment: .topLeading)
                }
                .frame(width: cardWidth)

                GlassCard(title: "UV指数", systemImage: "sun.max") {
                    UVGaugeView(value: weather.uvIndex)
                }
                .frame(width: cardWidth)

                GlassCard(title: "風", systemImage: "wind") {
                    WindCompassView(direction: weather.windDirection, speed: weather.windSpeed, units: units)
                }
                .frame(width: cardWidth)

                GlassCard(title: "湿度", systemImage: "humidity") {
                    HumidityView(value: weather.humidity, visibility: weather.visibility, units: units)
                }
                .frame(width: cardWidth)

                GlassCard(title: "気圧", systemImage: "gauge.with.needle") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(format: "%.\(units.pressureFractionDigits)f", units.pressure(weather.pressure)))
                            .font(.system(.title, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                        + Text(" \(units.pressureUnit)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(pressureComment)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: cardMinHeight, alignment: .topLeading)
                }
                .frame(width: cardWidth)

                GlassCard(title: "日の出・日の入り", systemImage: "sunrise") {
                    SunArcView(sunrise: weather.sunrise, sunset: weather.sunset, now: Date(), timeZone: weather.timeZone)
                }
                .frame(width: cardWidth)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("日の出 \(weather.sunrise.timeLabel(in: weather.timeZone))、日の入り \(weather.sunset.timeLabel(in: weather.timeZone))")
            }
            .padding(.vertical, 2)
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

// MARK: - 傘指数(降水確率から「傘が要るか」を一言で伝える、そらだま独自の項目)

struct UmbrellaIndexView: View {
    @ScaledMetric(relativeTo: .body) private var cardMinHeight: CGFloat = 96
    let probability: Double?

    private var judgement: (String, Color) {
        guard let probability else { return ("情報なし", Color.white.opacity(0.6)) }
        switch probability {
        case ..<20: return ("不要でしょう", Color(red: 0.55, green: 0.85, blue: 0.6))
        case 20..<50: return ("念のため持って", Color(red: 1.0, green: 0.82, blue: 0.4))
        default: return ("傘が必須です", Color(red: 0.55, green: 0.75, blue: 1.0))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int((probability ?? 0).rounded()))")
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                Text("%")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(judgement.0)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(judgement.1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: cardMinHeight, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("これから数時間の降水確率\(Int((probability ?? 0).rounded()))パーセント、\(judgement.0)")
    }
}

// MARK: - 洗濯指数(湿度・風・降水確率から外干しのしやすさを判定する、そらだま独自の項目)

struct LaundryIndexView: View {
    @ScaledMetric(relativeTo: .body) private var cardMinHeight: CGFloat = 96
    let humidity: Double
    let windSpeed: Double
    let precipProbability: Double?

    /// 0〜100 のスコア。降水確率が高い/湿度が高いほど下がり、風があると少し上がる。
    private var score: Int {
        var value = 100.0
        value -= (precipProbability ?? 0) * 0.9
        value -= max(0, humidity - 40) * 0.8
        value += min(windSpeed, 8) * 3
        return Int(value.clamped(to: 0...100).rounded())
    }

    private var judgement: (String, Color) {
        switch score {
        case 80...: return ("よく乾きます", Color(red: 0.55, green: 0.85, blue: 0.6))
        case 60..<80: return ("外干しOK", Color(red: 0.75, green: 0.88, blue: 0.55))
        case 40..<60: return ("部屋干し推奨", Color(red: 1.0, green: 0.82, blue: 0.4))
        case 20..<40: return ("乾きにくいです", Color(red: 1.0, green: 0.62, blue: 0.35))
        default: return ("外干しは控えて", Color(red: 0.60, green: 0.75, blue: 1.0))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(score)")
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                Text("点")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(judgement.0)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(judgement.1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: cardMinHeight, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("洗濯指数\(score)点、\(judgement.0)")
    }
}

// MARK: - 日の出・日の入りリング

/// 日の出から日の入りまでの経過を円環リングで示す。
/// Apple 純正「天気」アプリの、横棒トラック上を太陽の玉が移動するアークとは異なり、
/// アプリ内の UV 指数(UVGaugeView)と同じ「リングゲージ」の語彙に統一した表現。
struct SunArcView: View {
    @ScaledMetric(relativeTo: .body) private var cardMinHeight: CGFloat = 96
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
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.72, blue: 0.35), Color(red: 1.0, green: 0.88, blue: 0.55)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                WeatherIconView(kind: .clear, isDay: true)
                    .frame(width: 22, height: 22)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                // 夜明け前(now < sunrise)を「日中です」と誤表示しないよう3状態で判定
                Text(now < sunrise ? "夜明け前です" : (now > sunset ? "日没しました" : "日中です"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text("日の出 \(sunrise.timeLabel(in: timeZone))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                Text("日の入り \(sunset.timeLabel(in: timeZone))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: cardMinHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("日の出 \(sunrise.timeLabel(in: timeZone))、日の入り \(sunset.timeLabel(in: timeZone))")
    }
}

// MARK: - 風向インジケーター

/// 風向を示す矢印バッジ。(Apple 純正「天気」アプリの目盛り付きコンパスとは異なる、
/// バッジ+テキストのシンプルな表現)
struct WindCompassView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var cardMinHeight: CGFloat = 96
    let direction: Double // 風が「吹いてくる」方角(度)
    let speed: Double     // m/s(表示時に units で変換する)
    var units: UnitSystem = .celsius

    /// 16方位の日本語名(VoiceOver 用)
    static func directionName(_ degrees: Double) -> String {
        let names = ["北", "北北東", "北東", "東北東", "東", "東南東", "南東", "南南東",
                     "南", "南南西", "南西", "西南西", "西", "西北西", "北西", "北北西"]
        // 負値・NaN でも配列外アクセスしないよう 0..<360 に正規化してから方位に変換
        guard degrees.isFinite else { return names[0] }
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int(((normalized + 11.25) / 22.5).rounded(.down)) % 16
        return names[index]
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                Image(systemName: "arrow.up")
                    .font(.system(.title2).weight(.bold))
                    .foregroundStyle(Color(red: 0.55, green: 0.85, blue: 1.0))
                    .rotationEffect(.degrees(direction + 180))
                    .animation(reduceMotion ? nil : .spring(duration: 1.0), value: direction)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.directionName(direction))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 3) {
                    Text(String(format: "%.0f", units.windSpeed(speed)))
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                    Text(units.windSpeedUnit)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: cardMinHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.directionName(direction))の風、秒速\(Int(speed.rounded()))メートル")
    }
}

// MARK: - UV インデックスリング

/// UV 指数を円形リングで示す独自デザイン。
/// (Apple 純正「天気」アプリの横棒ゲージとは異なるリング表現)
struct UVGaugeView: View {
    @ScaledMetric(relativeTo: .body) private var cardMinHeight: CGFloat = 96
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
                    .font(.system(.title3, design: .rounded).weight(.semibold))
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
        .frame(minHeight: cardMinHeight, alignment: .leading)
    }
}

// MARK: - 湿度(視程を併記)

struct HumidityView: View {
    @ScaledMetric(relativeTo: .body) private var cardMinHeight: CGFloat = 96
    let value: Double
    var visibility: Double? = nil
    var units: UnitSystem = .celsius

    private var visibilityLabel: String? {
        guard let visibility else { return nil }
        return String(format: "視程 %.1f%@", units.distance(visibility), units.distanceUnit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(Int(value.rounded()))%")
                .font(.system(.title, design: .rounded).weight(.semibold))
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
            if let visibilityLabel {
                Text(visibilityLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: cardMinHeight, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("湿度\(Int(value.rounded()))パーセント" + (visibilityLabel.map { "、\($0)" } ?? ""))
    }
}
