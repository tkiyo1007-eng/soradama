import SwiftUI

/// 「そらだま」ブランドの背景。
///
/// Apple 純正「天気」アプリは画面右上に太陽/月を模した発光体を置き、
/// 画面全体を"写実的な空"として再現する。そらだまは天候・時間帯を示す
/// 発光体やオーブを画面上に一切置かず、グラデーションと光の帯・降水粒子のみで
/// 抽象的にトーンを示す。天候の種類自体は現在気温ヘッダー内の小さなアイコン
/// (WeatherIconView)でのみ表す。
struct SkyBackground: View {
    let kind: WeatherKind
    let isDay: Bool
    /// 日の出・日の入り。渡されると、その日の時刻に応じて
    /// 朝焼け・夕焼けを含む連続的な空の色になる。
    var sunrise: Date?
    var sunset: Date?
    /// 静止画として描く場合の固定時刻。壁紙の書き出しのように
    /// `ImageRenderer` で描画する場面では、`TimelineView` の中身が
    /// 描かれないため、この値を渡してアニメーションなしで構成する。
    var staticTime: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 静止画モードでは「動きを減らす」設定と同じ扱いにして、時刻固定の見た目にする
    private var isStatic: Bool { staticTime != nil }

    /// 日の出・日の入りが分かる場合は時刻連動の色、分からない場合は従来の昼夜2段階
    private var colors: [Color] {
        if let sunrise, let sunset {
            return kind.skyColors(at: Date(), sunrise: sunrise, sunset: sunset)
        }
        return kind.skyColors(isDay: isDay)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colors,
                startPoint: .top,
                endPoint: .bottom
            )
            .animation(.easeInOut(duration: 1.2), value: kind)
            .animation(.easeInOut(duration: 1.2), value: isDay)

            RibbonDrift(
                dark: !isDay || kind == .thunderstorm,
                reduceMotion: reduceMotion || isStatic
            )

            if !reduceMotion || isStatic {
                WeatherParticles(kind: kind.particle, staticTime: staticTime)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 帯状のリボン雲 — Apple 純正のぼかし楕円の雲塊とは異なる、細い光の帯の表現

private struct RibbonDrift: View {
    let dark: Bool
    let reduceMotion: Bool

    var body: some View {
        Group {
            if reduceMotion {
                // 動きなしの場合は TimelineView を挟まない。
                // ImageRenderer は TimelineView の中身を描画しないため、
                // 壁紙の書き出しでも帯が確実に写るようにする狙いもある。
                ribbons(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    ribbons(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func ribbons(time: TimeInterval) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                ribbon(width: width, time: time, speed: 7, y: 90, thickness: 22, opacity: dark ? 0.10 : 0.22)
                ribbon(width: width, time: time, speed: -4.5, y: 165, thickness: 14, opacity: dark ? 0.08 : 0.16)
                ribbon(width: width, time: time, speed: 3, y: 235, thickness: 10, opacity: dark ? 0.06 : 0.12)
            }
        }
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
