import SwiftUI

/// 「そらだま」ブランドの背景。
///
/// Apple 純正「天気」アプリは画面全体を"写実的な空"として再現する
/// (太陽の光条・満天の星・輪郭のぼやけた雲塊が画面を横切る・雷雨時は画面全体が閃光)。
/// そらだまはこれとは異なる視覚言語を採る: 天候はヘッダー背後の一つの「玉(オーブ)」に
/// 集約して表現し、画面全体を写実的な空として演出することはしない。
struct SkyBackground: View {
    let kind: WeatherKind
    let isDay: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: kind.skyColors(isDay: isDay),
                startPoint: .top,
                endPoint: .bottom
            )
            .animation(.easeInOut(duration: 1.2), value: kind)
            .animation(.easeInOut(duration: 1.2), value: isDay)

            RibbonDrift(dark: !isDay || kind == .thunderstorm, reduceMotion: reduceMotion)

            OrbMotif(kind: kind, isDay: isDay, reduceMotion: reduceMotion)

            if !reduceMotion {
                WeatherParticles(kind: kind.particle)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 空玉(そらだま)オーブ — 天候をひとつの玉に集約して表現する独自モチーフ

/// Apple 純正の「写実的な太陽/月/星空」の代わりに、天候を一つの発光する玉で抽象的に示す。
/// 玉の色・輝き・内側のきらめきが天候と昼夜で変化する。
private struct OrbMotif: View {
    let kind: WeatherKind
    let isDay: Bool
    let reduceMotion: Bool

    private var glowColor: Color {
        switch (kind, isDay) {
        case (.clear, true), (.partlyCloudy, true):
            return Color(red: 1.0, green: 0.86, blue: 0.55)
        case (.clear, false), (.partlyCloudy, false):
            return Color(red: 0.70, green: 0.78, blue: 1.0)
        case (.thunderstorm, _):
            return Color(red: 0.85, green: 0.70, blue: 1.0)
        default:
            return Color.white
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            GeometryReader { proxy in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let pulse = reduceMotion ? 0 : (sin(time * 0.6) + 1) / 2
                let center = CGPoint(x: proxy.size.width * 0.80, y: proxy.size.height * 0.11)

                ZStack {
                    // 玉の外周のにじみ
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [glowColor.opacity(0.55), glowColor.opacity(0.12), .clear],
                                center: .center,
                                startRadius: 4,
                                endRadius: 150 + pulse * 14
                            )
                        )
                        .frame(width: 300, height: 300)
                        .position(center)
                        .blendMode(.screen)

                    // 玉本体(ガラス玉のような質感)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.9), glowColor.opacity(0.7), glowColor.opacity(0.25)],
                                center: UnitPoint(x: 0.35, y: 0.3),
                                startRadius: 2,
                                endRadius: 46
                            )
                        )
                        .frame(width: 58, height: 58)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                        )
                        .position(center)
                        .shadow(color: glowColor.opacity(0.6), radius: 16 + pulse * 6)

                    // 玉の中のきらめき(満天の星ではなく、玉の周りだけの少数のきらめき)
                    if !isDay {
                        SparkleCluster(center: center, time: time, reduceMotion: reduceMotion)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 玉の周りだけに漂う数個のきらめき。画面全体を覆う星空ではない点が Apple 純正との違い。
private struct SparkleCluster: View {
    let center: CGPoint
    let time: TimeInterval
    let reduceMotion: Bool

    var body: some View {
        Canvas { context, _ in
            var generator = SeededRandom(seed: 11)
            for _ in 0..<10 {
                let angle = generator.next() * .pi * 2
                let radius = 40 + generator.next() * 70
                let x = center.x + cos(angle) * radius
                let y = center.y + sin(angle) * radius * 0.7
                let phase = generator.next() * .pi * 2
                let twinkle = reduceMotion ? 0.6 : (sin(time * 1.4 + phase) + 1) / 2
                let dotRadius = 1.0 + generator.next() * 1.4
                let rect = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.25 + twinkle * 0.6)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 帯状のリボン雲 — Apple 純正のぼかし楕円の雲塊とは異なる、細い光の帯の表現

private struct RibbonDrift: View {
    let dark: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            GeometryReader { proxy in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let width = proxy.size.width

                ZStack {
                    ribbon(width: width, time: time, speed: 7, y: 90, thickness: 22, opacity: dark ? 0.10 : 0.22)
                    ribbon(width: width, time: time, speed: -4.5, y: 165, thickness: 14, opacity: dark ? 0.08 : 0.16)
                    ribbon(width: width, time: time, speed: 3, y: 235, thickness: 10, opacity: dark ? 0.06 : 0.12)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func ribbon(width: Double, time: TimeInterval, speed: Double, y: Double, thickness: Double, opacity: Double) -> some View {
        let span = width + 260
        let progress = (time * abs(speed)).truncatingRemainder(dividingBy: span)
        let x = speed >= 0 ? progress - 130 : width - progress + 130
        return Capsule()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(opacity), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: span, height: thickness)
            .rotationEffect(.degrees(-3))
            .position(x: x, y: y)
    }
}

// MARK: - 決定的な擬似乱数(フレーム間で位置を固定するため)

struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let value = (state >> 33) & 0x7FFFFFFF
        return Double(value) / Double(0x7FFFFFFF)
    }
}

#Preview {
    SkyBackground(kind: .clear, isDay: false)
}
