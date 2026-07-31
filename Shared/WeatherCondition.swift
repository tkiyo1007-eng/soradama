import SwiftUI

/// WMO 天気コードをデザイン上の「天候の種類」へマッピングする。
/// 背景グラデーション・パーティクル・SF Symbols をすべてここから導出する。
enum WeatherKind: String, Codable, CaseIterable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case snow
    case thunderstorm

    init(wmoCode: Int) {
        switch wmoCode {
        case 0, 1:         self = .clear // WMO 1 は「おおむね晴れ」なので晴れ扱いにする
        case 2:            self = .partlyCloudy
        case 3:            self = .cloudy
        case 45, 48:       self = .fog
        case 51...57:      self = .drizzle
        case 61...67:      self = .rain
        case 71...77:      self = .snow
        case 80...82:      self = .rain
        case 85, 86:       self = .snow
        case 95...99:      self = .thunderstorm
        default:           self = .cloudy
        }
    }

    /// 日本語の天気ラベル
    var label: String {
        switch self {
        case .clear:         return "晴れ"
        case .partlyCloudy:  return "晴れ時々くもり"
        case .cloudy:        return "くもり"
        case .fog:           return "霧"
        case .drizzle:       return "霧雨"
        case .rain:          return "雨"
        case .snow:          return "雪"
        case .thunderstorm:  return "雷雨"
        }
    }

    func symbolName(isDay: Bool) -> String {
        switch self {
        case .clear:         return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy:  return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy:        return "cloud.fill"
        case .fog:           return "cloud.fog.fill"
        case .drizzle:       return "cloud.drizzle.fill"
        case .rain:          return "cloud.rain.fill"
        case .snow:          return "cloud.snow.fill"
        case .thunderstorm:  return "cloud.bolt.rain.fill"
        }
    }

    /// 空のグラデーション(上 → 下)
    func skyColors(isDay: Bool) -> [Color] {
        switch (self, isDay) {
        case (.clear, true):
            return [Color(red: 0.10, green: 0.42, blue: 0.86),
                    Color(red: 0.33, green: 0.66, blue: 0.96),
                    Color(red: 0.62, green: 0.85, blue: 0.98)]
        case (.clear, false):
            return [Color(red: 0.02, green: 0.03, blue: 0.12),
                    Color(red: 0.07, green: 0.10, blue: 0.28),
                    Color(red: 0.15, green: 0.20, blue: 0.42)]
        case (.partlyCloudy, true):
            return [Color(red: 0.16, green: 0.42, blue: 0.78),
                    Color(red: 0.40, green: 0.62, blue: 0.86),
                    Color(red: 0.66, green: 0.79, blue: 0.90)]
        case (.partlyCloudy, false):
            return [Color(red: 0.04, green: 0.06, blue: 0.16),
                    Color(red: 0.12, green: 0.16, blue: 0.32),
                    Color(red: 0.22, green: 0.27, blue: 0.44)]
        case (.cloudy, true), (.fog, true):
            return [Color(red: 0.35, green: 0.42, blue: 0.53),
                    Color(red: 0.51, green: 0.58, blue: 0.67),
                    Color(red: 0.68, green: 0.73, blue: 0.79)]
        case (.cloudy, false), (.fog, false):
            return [Color(red: 0.09, green: 0.11, blue: 0.16),
                    Color(red: 0.17, green: 0.20, blue: 0.27),
                    Color(red: 0.26, green: 0.30, blue: 0.38)]
        case (.drizzle, true), (.rain, true):
            return [Color(red: 0.20, green: 0.28, blue: 0.42),
                    Color(red: 0.32, green: 0.42, blue: 0.56),
                    Color(red: 0.45, green: 0.55, blue: 0.66)]
        case (.drizzle, false), (.rain, false):
            return [Color(red: 0.04, green: 0.06, blue: 0.12),
                    Color(red: 0.10, green: 0.14, blue: 0.24),
                    Color(red: 0.17, green: 0.23, blue: 0.34)]
        case (.snow, true):
            return [Color(red: 0.55, green: 0.63, blue: 0.75),
                    Color(red: 0.70, green: 0.77, blue: 0.86),
                    Color(red: 0.85, green: 0.89, blue: 0.94)]
        case (.snow, false):
            return [Color(red: 0.08, green: 0.11, blue: 0.20),
                    Color(red: 0.16, green: 0.21, blue: 0.33),
                    Color(red: 0.28, green: 0.34, blue: 0.47)]
        case (.thunderstorm, _):
            return [Color(red: 0.05, green: 0.04, blue: 0.12),
                    Color(red: 0.13, green: 0.11, blue: 0.26),
                    Color(red: 0.24, green: 0.20, blue: 0.38)]
        }
    }

    /// 時刻に応じた空の色。日の出・日の入りを基準に、
    /// 夜明け前 → 朝焼け → 日中 → 夕暮れ → 夜 を連続的に補間する。
    /// 「空そのものをデザインにした」というアプリのコンセプトを、
    /// 開く時間帯ごとに違う色として表現するためのもの。
    func skyColors(at date: Date, sunrise: Date, sunset: Date) -> [Color] {
        let base = skyColors(isDay: true)
        let night = skyColors(isDay: false)

        // 日の出/日の入りの前後1時間を「マジックアワー」として扱う
        let window: TimeInterval = 3600
        let time = date.timeIntervalSince1970
        let riseTime = sunrise.timeIntervalSince1970
        let setTime = sunset.timeIntervalSince1970

        // 天気が悪い日は朝焼け・夕焼けの赤みを控えめにする(曇り空では実際にも映えない)
        let warmthScale: Double
        switch self {
        case .clear:        warmthScale = 1.0
        case .partlyCloudy: warmthScale = 0.8
        case .cloudy, .fog: warmthScale = 0.45
        default:            warmthScale = 0.3
        }

        if time < riseTime - window || time > setTime + window {
            return night
        }
        if time < riseTime + window {
            // 夜明け: 夜の色 → 朝焼け → 日中の色
            let progress = ((time - (riseTime - window)) / (window * 2)).clamped(to: 0...1)
            return Self.blendThroughGlow(
                from: night, to: base, progress: progress,
                glow: Self.dawnGlow, warmthScale: warmthScale
            )
        }
        if time > setTime - window {
            // 日暮れ: 日中の色 → 夕焼け → 夜の色
            let progress = ((time - (setTime - window)) / (window * 2)).clamped(to: 0...1)
            return Self.blendThroughGlow(
                from: base, to: night, progress: progress,
                glow: Self.duskGlow, warmthScale: warmthScale
            )
        }
        return base
    }

    /// 朝焼けの色(下方が明るいオレンジ〜桃色)
    private static let dawnGlow = [
        Color(red: 0.16, green: 0.22, blue: 0.48),
        Color(red: 0.72, green: 0.42, blue: 0.52),
        Color(red: 1.00, green: 0.72, blue: 0.52),
    ]

    /// 夕焼けの色(より濃い赤・紫寄り)
    private static let duskGlow = [
        Color(red: 0.20, green: 0.18, blue: 0.42),
        Color(red: 0.78, green: 0.36, blue: 0.38),
        Color(red: 1.00, green: 0.64, blue: 0.36),
    ]

    /// from → glow → to と2段階で色を混ぜる(progress 0.5 のとき glow が最も強い)
    private static func blendThroughGlow(
        from: [Color], to: [Color], progress: Double, glow: [Color], warmthScale: Double
    ) -> [Color] {
        let straight = zip(from, to).map { $0.blended(with: $1, amount: progress) }
        // 中間ほど glow を強く乗せる(三角波)
        let glowAmount = (1 - abs(progress - 0.5) * 2) * warmthScale
        return zip(straight, glow).map { $0.blended(with: $1, amount: glowAmount * 0.75) }
    }

    /// パーティクル演出の種類
    var particle: ParticleKind {
        switch self {
        case .rain, .thunderstorm: return .rain
        case .drizzle:             return .drizzle
        case .snow:                return .snow
        default:                   return .none
        }
    }

    var hasCloudLayer: Bool {
        switch self {
        case .clear: return false
        default:     return true
        }
    }
}

enum ParticleKind {
    case none, rain, drizzle, snow
}
