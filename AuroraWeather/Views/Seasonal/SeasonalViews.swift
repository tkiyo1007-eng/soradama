import SwiftUI
import Combine

// MARK: - 環境値

private struct SeasonalContextKey: EnvironmentKey {
    static let defaultValue = SeasonalContext.none
}

extension EnvironmentValues {
    var seasonalContext: SeasonalContext {
        get { self[SeasonalContextKey.self] }
        set { self[SeasonalContextKey.self] = newValue }
    }
}

// MARK: - 日付の追随

/// 季節演出の判定を、前面復帰・日付変更・時刻/タイムゾーン変更・表示中の0時で作り直す。
/// 起動時の値を持ち続けると、11月1日以降もハロウィン表示が残るため。
private struct SeasonalClock: ViewModifier {
    @Binding var context: SeasonalContext
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                    .merge(with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange))
                    .merge(with: NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification))
                    .receive(on: DispatchQueue.main)
            ) { _ in
                refresh()
            }
            .task(id: context) {
                // 通知が届かない場合に備え、表示中は次の0時に判定し直す。
                let calendar = Calendar.current
                let now = Date()
                guard let midnight = calendar.date(
                    byAdding: .day, value: 1, to: calendar.startOfDay(for: now)
                ) else { return }
                try? await Task.sleep(for: .seconds(max(1, midnight.timeIntervalSince(now) + 1)))
                guard !Task.isCancelled else { return }
                refresh()
            }
    }

    private func refresh() {
        let updated = SeasonalContext.current()
        if updated != context { context = updated }
    }
}

extension SeasonalContext {
    /// 端末の現在時刻から作る。DEBUGビルドだけ、画面確認用に期間判定の日付を
    /// 起動引数 `-SoradamaQASeasonalDate 2026-10-15` で差し替えられる。
    /// 差し替えるのは期間判定だけで、空玉の記録日や保存データには影響しない。
    static func current(now: Date = Date(), calendar: Calendar = .current) -> SeasonalContext {
        #if DEBUG
        if let text = UserDefaults.standard.string(forKey: "SoradamaQASeasonalDate") {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            if let override = formatter.date(from: text)?.addingTimeInterval(12 * 60 * 60) {
                return SeasonalContext(
                    event: SeasonalEvent.active(at: override, calendar: calendar),
                    todayKey: SeasonalEvent.dayKey(for: now, calendar: calendar)
                )
            }
        }
        #endif
        return .live(now: now, calendar: calendar)
    }
}

extension View {
    func seasonalClock(_ context: Binding<SeasonalContext>) -> some View {
        modifier(SeasonalClock(context: context))
    }

    /// 開催中の今日の空玉だけに、オレンジと紫の光の輪とジャックオランタンを添える。
    /// 玉の中の天気の色には重ねず、レイアウト・タップ領域・読み上げは変えない。
    @ViewBuilder
    func halloweenOrbAccent(_ isOn: Bool, size: CGFloat) -> some View {
        if isOn {
            self
                .background {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        HalloweenPalette.pumpkin.opacity(0.75),
                                        HalloweenPalette.violet.opacity(0.5),
                                        .clear,
                                    ],
                                    center: .center,
                                    startRadius: size * 0.4,
                                    endRadius: size * 0.85
                                )
                            )
                        Circle()
                            .strokeBorder(HalloweenPalette.pumpkin.opacity(0.9), lineWidth: max(1.5, size * 0.035))
                            .frame(width: size * 1.12, height: size * 1.12)
                    }
                    .frame(width: size * 1.7, height: size * 1.7)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .overlay(alignment: .bottomTrailing) {
                    JackOLanternMark()
                        .frame(width: max(14, size * 0.44), height: max(14, size * 0.44))
                        .offset(x: size * 0.14, y: size * 0.1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        } else {
            self
        }
    }
}

// MARK: - 色と印

enum HalloweenPalette {
    static let pumpkin = Color(red: 1.0, green: 0.52, blue: 0.12)
    static let amber = Color(red: 1.0, green: 0.70, blue: 0.34)
    static let violet = Color(red: 0.62, green: 0.44, blue: 0.95)
    static let night = Color(red: 0.16, green: 0.06, blue: 0.30)
    /// 濃い紫・焦げ茶のカード上で読める明るさの琥珀色(本文ではなく短い見出しに使う)
    static let text = Color(red: 1.0, green: 0.82, blue: 0.56)

    /// 期間中のカード背景。白い文字が読める暗さを保つ。
    static let cardBackground = LinearGradient(
        colors: [
            Color(red: 0.30, green: 0.12, blue: 0.42).opacity(0.94),
            Color(red: 0.50, green: 0.20, blue: 0.10).opacity(0.94),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// 空玉オリジナルのジャックオランタン。かぼちゃの実に、光る目と口をくり抜いた形。
struct JackOLanternMark: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let glow = Color(red: 1.0, green: 0.92, blue: 0.45)
            ZStack {
                ForEach([-0.24, 0.24, 0.0], id: \.self) { offset in
                    Ellipse()
                        .fill(
                            LinearGradient(
                                colors: [HalloweenPalette.pumpkin, Color(red: 0.85, green: 0.34, blue: 0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: w * (offset == 0 ? 0.58 : 0.52), height: h * 0.76)
                        .offset(x: w * offset, y: h * 0.1)
                }
                Capsule()
                    .fill(Color(red: 0.40, green: 0.55, blue: 0.28))
                    .frame(width: w * 0.12, height: h * 0.22)
                    .rotationEffect(.degrees(12))
                    .offset(y: -h * 0.36)
                // 目
                ForEach([-0.17, 0.17], id: \.self) { x in
                    UpTriangle()
                        .fill(glow)
                        .frame(width: w * 0.18, height: h * 0.15)
                        .offset(x: w * x, y: -h * 0.02)
                }
                // 口
                JaggedMouth()
                    .fill(glow)
                    .frame(width: w * 0.5, height: h * 0.16)
                    .offset(y: h * 0.24)
            }
            .frame(width: w, height: h)
            .shadow(color: HalloweenPalette.pumpkin.opacity(0.7), radius: w * 0.2)
        }
    }
}

private struct UpTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct JaggedMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let teeth = 4
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        for index in 0...teeth * 2 {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(teeth * 2)
            let y = index.isMultiple(of: 2) ? rect.minY : rect.minY + rect.height * 0.45
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.6)
        )
        path.closeSubpath()
        return path
    }
}

/// こうもりのシルエット。
private struct BatShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: p(0.5, 0.3))
        path.addLine(to: p(0.46, 0.14))            // 左耳
        path.addLine(to: p(0.43, 0.3))
        path.addQuadCurve(to: p(0.0, 0.18), control: p(0.22, 0.02))
        path.addQuadCurve(to: p(0.12, 0.62), control: p(0.02, 0.42))
        path.addQuadCurve(to: p(0.25, 0.56), control: p(0.18, 0.52))
        path.addQuadCurve(to: p(0.36, 0.68), control: p(0.32, 0.56))
        path.addQuadCurve(to: p(0.5, 0.82), control: p(0.44, 0.7))
        path.addQuadCurve(to: p(0.64, 0.68), control: p(0.56, 0.7))
        path.addQuadCurve(to: p(0.75, 0.56), control: p(0.68, 0.56))
        path.addQuadCurve(to: p(0.88, 0.62), control: p(0.82, 0.52))
        path.addQuadCurve(to: p(1.0, 0.18), control: p(0.98, 0.42))
        path.addQuadCurve(to: p(0.57, 0.3), control: p(0.78, 0.02))
        path.addLine(to: p(0.54, 0.14))            // 右耳
        path.closeSubpath()
        return path
    }
}

// MARK: - 背景

/// 期間中の空。天気の空の上に夜の紫と夕焼けのオレンジを重ね、月とこうもりを置く。
/// 天気アイコン・数値・文字はこの上に描かれるため、天気の意味は変わらない。
/// こうもりはゆっくり横切るだけで点滅しない。「動きを減らす」では止めて描く。
struct HalloweenSkyGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: HalloweenPalette.night.opacity(0.62), location: 0.0),
                    .init(color: HalloweenPalette.night.opacity(0.32), location: 0.45),
                    .init(color: HalloweenPalette.pumpkin.opacity(0.22), location: 0.75),
                    .init(color: HalloweenPalette.pumpkin.opacity(0.42), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                let width = proxy.size.width
                moon
                    .frame(width: 74, height: 74)
                    .position(x: width - 58, y: 178)

                if reduceMotion {
                    bats(width: width, time: 0)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                        bats(width: width, time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var moon: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(red: 1.0, green: 0.97, blue: 0.82), Color(red: 1.0, green: 0.84, blue: 0.52)],
                    center: UnitPoint(x: 0.4, y: 0.35),
                    startRadius: 2,
                    endRadius: 40
                )
            )
            .overlay {
                // うっすらとした模様
                Circle()
                    .fill(Color(red: 0.92, green: 0.72, blue: 0.42).opacity(0.35))
                    .frame(width: 16, height: 16)
                    .offset(x: 12, y: 10)
            }
            .shadow(color: Color(red: 1.0, green: 0.78, blue: 0.40).opacity(0.8), radius: 22)
    }

    /// 4匹がそれぞれの速さで横切る。time = 0 は静止画用の固定配置。
    private func bats(width: CGFloat, time: TimeInterval) -> some View {
        let flock: [(speed: Double, y: Double, size: Double, phase: Double)] = [
            (14, 120, 42, 0.10),
            (-10, 205, 32, 0.55),
            (18, 285, 26, 0.80),
            (-12, 340, 36, 0.30),
        ]
        return ZStack {
            ForEach(Array(flock.enumerated()), id: \.offset) { _, bat in
                let span = Double(width) + 80
                let travel = (time * abs(bat.speed) + bat.phase * span).truncatingRemainder(dividingBy: span)
                let x = bat.speed >= 0 ? travel - 40 : Double(width) + 40 - travel
                let bob = sin(time * 1.3 + bat.phase * 6) * 6
                let flap = time == 0 ? 1.0 : 0.72 + 0.28 * abs(sin(time * 5 + bat.phase * 9))
                BatShape()
                    .fill(Color(red: 0.08, green: 0.03, blue: 0.12).opacity(0.9))
                    .frame(width: bat.size, height: bat.size * 0.6)
                    .scaleEffect(x: 1, y: flap)
                    .position(x: x, y: bat.y + bob)
            }
        }
    }
}

// MARK: - 未記録の日の期間案内

/// 開催中に今日の空玉がまだ無いとき(取得中・通信失敗・保存済みの天気だけ)に出す。
/// 記録済みとは言わず、記録される条件と取り直す操作だけを伝える。
struct SeasonalRecordHint: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            JackOLanternMark()
                .frame(width: 30, height: 30)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("ハロウィンの空玉は10月31日まで")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HalloweenPalette.text)
                Text("自分の空の天気を取得できた日は、その日の空玉に秋の灯りが添えられます。下に引くと、もう一度取得できます。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(HalloweenPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(HalloweenPalette.pumpkin.opacity(0.55), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
