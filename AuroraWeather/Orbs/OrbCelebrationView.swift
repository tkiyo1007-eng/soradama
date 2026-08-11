import SwiftUI

/// 特別な日に空玉が生まれたときの、画面いっぱいのお祝い。
///
/// 通常の日は控えめなトーストのままにして、二十四節気・満月・連続記録の節目という
/// 「その日だけ」の出来事に限ってこの演出を出す。毎日出すと特別さが失われるため。
struct OrbCelebrationView: View {
    let orb: DailyOrb
    let event: OrbRecordResult
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var orbScale: CGFloat = 0.3
    @State private var rayOpacity: Double = 0

    /// 見出し。節気 > 満月 > 連続記録の節目 の順に優先する。
    private var title: String {
        if let term = event.solarTerm { return String(localized: "今日は\(term.label)") }
        if event.isFullMoon { return String(localized: "満月の夜です") }
        if event.streak >= 7 { return String(localized: "\(event.streak)日連続、達成") }
        return String(localized: "特別な空玉が生まれました")
    }

    private var message: String {
        if let term = event.solarTerm { return term.poem }
        if event.isFullMoon { return String(localized: "まんまるの月が、玉のなかに映りました") }
        if event.streak >= 7 { return String(localized: "毎日の空が、これだけ集まりました") }
        return String(localized: "今日の空は、少し特別なかたちで残ります")
    }

    /// 演出の基調色。節気なら季節の色、満月なら月の色。
    private var accent: Color {
        if let term = event.solarTerm {
            let c = term.accent
            return Color(red: c.r, green: c.g, blue: c.b)
        }
        if event.isFullMoon { return Color(red: 1.0, green: 0.95, blue: 0.78) }
        return Color(red: 0.72, green: 0.62, blue: 1.0)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // 玉の背後から放射する光
            if !reduceMotion {
                RadiantRays(color: accent)
                    .opacity(rayOpacity)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 22) {
                OrbView(orb: orb, size: 190)
                    .scaleEffect(orbScale)
                    .shadow(color: accent.opacity(0.7), radius: 40)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                Button("空玉を見る") { onDismiss() }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color(red: 0.10, green: 0.12, blue: 0.28))
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(.white, in: Capsule())
                    .opacity(appeared ? 1 : 0)
                    .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)。\(message)")
        .onAppear {
            guard !reduceMotion else {
                orbScale = 1
                appeared = true
                rayOpacity = 1
                return
            }
            withAnimation(.spring(response: 0.65, dampingFraction: 0.6)) { orbScale = 1 }
            withAnimation(.easeOut(duration: 1.1)) { rayOpacity = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.35)) { appeared = true }
        }
    }
}

/// 中心から広がる光条。特別な日の空玉を後ろから照らす。
private struct RadiantRays: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
                let maxLength = max(size.width, size.height)
                // ゆっくり回りながら、長さが呼吸するように伸縮する
                for index in 0..<16 {
                    let base = Double(index) / 16 * 360 + time * 6
                    let radians = base * .pi / 180
                    let wave = (sin(time * 1.3 + Double(index)) + 1) / 2
                    let length = maxLength * (0.35 + wave * 0.25)
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: CGPoint(
                        x: center.x + cos(radians) * length,
                        y: center.y + sin(radians) * length
                    ))
                    context.stroke(
                        path,
                        with: .color(color.opacity(0.10 + wave * 0.10)),
                        style: StrokeStyle(lineWidth: 14 + wave * 10, lineCap: .round)
                    )
                }
            }
            .blendMode(.screen)
            .blur(radius: 12)
        }
    }
}
