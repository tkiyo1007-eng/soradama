import SwiftUI

// MARK: - 空玉の描画

/// その日の天気が閉じ込められたガラス玉。
/// 天気の種類×気温×日付シードから、同じ日は常に同じ、日が違えば少し違う模様になる。
struct OrbView: View {
    let orb: DailyOrb
    var size: CGFloat = 44
    /// クリスタル玉の明滅アニメーションを止めて静止画として描く。
    /// `ImageRenderer`(壁紙・共有カード)とウィジェットは `TimelineView` の中身を
    /// 描画しないため、その文脈では必ず false にすること。
    var animated: Bool = true
    /// 季節の景色(霞・入道雲・うろこ雲・光条)を重ねるか。
    /// 空玉ずかんの「天気」のマスは季節に依存しない見本なので false にする。
    var showsSeason: Bool = true

    /// 玉の中の空の色。時間帯によって朝焼け・夕暮れ・夜空に変わる。
    private var baseColors: [Color] {
        switch orb.timeOfDay {
        case .dawn:
            // 朝焼け: 藍から桃色へ抜ける
            return [Color(red: 0.36, green: 0.44, blue: 0.78),
                    Color(red: 0.98, green: 0.66, blue: 0.62),
                    Color(red: 1.0, green: 0.85, blue: 0.68)]
        case .dusk:
            // 夕暮れ: 紫から橙へ落ちる
            return [Color(red: 0.30, green: 0.26, blue: 0.60),
                    Color(red: 0.86, green: 0.44, blue: 0.52),
                    Color(red: 1.0, green: 0.68, blue: 0.42)]
        case .night:
            return orb.kind.skyColors(isDay: false)
        case .day:
            return orb.kind.skyColors(isDay: true)
        }
    }

    /// 気温による色味(暑い日は暖色、寒い日は氷色のにじみ)
    private var temperatureTint: Color? {
        if orb.tempMax >= 30 { return Color(red: 1.0, green: 0.55, blue: 0.30) }
        if orb.tempMax >= 25 { return Color(red: 1.0, green: 0.80, blue: 0.45) }
        if orb.tempMax < 5 { return Color(red: 0.60, green: 0.85, blue: 1.0) }
        return nil
    }

    /// 季節ごとの空気感。同じ晴れでも春は霞み、秋は澄む。
    private var seasonTint: (color: Color, opacity: Double)? {
        switch orb.season {
        case .spring: return (Color(red: 1.0, green: 0.85, blue: 0.90), 0.30) // 霞んだ桃色
        case .summer: return (Color(red: 1.0, green: 0.95, blue: 0.70), 0.22) // 強い陽射し
        case .autumn: return (Color(red: 0.45, green: 0.55, blue: 0.95), 0.20) // 高く澄んだ青
        case .winter: return (Color(red: 0.80, green: 0.92, blue: 1.0), 0.26)  // 冴えた冷気
        }
    }

    private var seed: UInt64 {
        stableSeed(for: orb.dateKey)
    }

    var body: some View {
        Group {
            if orb.isMilestone {
                CrystalOrbView(orb: orb, size: size, animated: animated)
            } else {
                regularOrb
            }
        }
        .accessibilityLabel(orb.isMilestone
            ? "\(orb.dateKey)の特別な空玉クリスタル、\(orb.season.label)の\(orb.timeOfDay.label)、\(orb.kind.label)"
            : "\(orb.dateKey)の空玉、\(orb.season.label)の\(orb.timeOfDay.label)、\(orb.kind.label)")
    }

    private var regularOrb: some View {
        ZStack {
            // 玉の中の空
            Circle()
                .fill(
                    LinearGradient(colors: baseColors, startPoint: .top, endPoint: .bottom)
                )

            // 気温のにじみ(下方から)
            if let tint = temperatureTint {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tint.opacity(0.55), .clear],
                            center: UnitPoint(x: 0.5, y: 0.95),
                            startRadius: 0,
                            endRadius: size * 0.75
                        )
                    )
            }

            // 夜の玉には星を散らす
            if orb.timeOfDay == .night {
                starField
                    .clipShape(Circle())
            }

            // 天気の模様
            weatherPattern
                .clipShape(Circle())

            // 季節の空気感(模様の上から薄くかぶせる)
            if showsSeason, let season = seasonTint {
                seasonLayer(season)
                    .clipShape(Circle())
            }

            // ガラスの質感: ハイライトとリム
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.75), .white.opacity(0.0)],
                        center: UnitPoint(x: 0.32, y: 0.24),
                        startRadius: 0,
                        endRadius: size * 0.34
                    )
                )
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.85), .white.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1, size * 0.025)
                )
        }
        .frame(width: size, height: size)
        .shadow(color: baseColors.first?.opacity(0.45) ?? .clear, radius: size * 0.12, y: size * 0.06)
    }

    /// 夜空の星。日付シードなので同じ日は同じ星並びになる。
    private var starField: some View {
        OrbCanvas(seed: seed &+ 0x5747, size: size) { context, generator in
            for _ in 0..<7 {
                let x = generator.next() * size
                let y = generator.next() * size * 0.8
                let radius = size * (0.012 + generator.next() * 0.018)
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.5 + generator.next() * 0.5)))
            }
        }
    }

    /// 季節の空気感を表すレイヤー。
    /// 色だけだと季節の差が伝わらないため、季節ごとに「形のある景色」を描く。
    @ViewBuilder
    private func seasonLayer(_ season: (color: Color, opacity: Double)) -> some View {
        switch orb.season {
        case .spring:
            // 霞: 横に流れるやわらかい帯が重なる
            ZStack {
                season.color.opacity(season.opacity * 0.7)
                    .mask(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.8), .white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                VStack(spacing: size * 0.10) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(Color.white.opacity(0.38 - Double(index) * 0.06))
                            .frame(height: size * 0.055)
                            .padding(.horizontal, size * CGFloat(0.10 + Double(index) * 0.06))
                    }
                }
                .offset(y: size * 0.14)
                .blur(radius: size * 0.035)
            }
        case .summer:
            // 入道雲: 下から白い塊が湧き上がる
            ZStack {
                RadialGradient(
                    colors: [season.color.opacity(season.opacity + 0.10), .clear],
                    center: UnitPoint(x: 0.28, y: 0.04),
                    startRadius: 0,
                    endRadius: size * 0.8
                )
                Canvas { context, canvasSize in
                    var generator = SeededRandom(seed: seed &+ 0x5CE7)
                    let baseY = canvasSize.height * 0.92
                    // 大きさの違う円を重ねて積乱雲のシルエットを作る
                    let blobs: [(CGFloat, CGFloat, CGFloat)] = [
                        (0.30, 0.74, 0.26), (0.50, 0.62, 0.32), (0.70, 0.76, 0.24),
                        (0.40, 0.86, 0.22), (0.62, 0.88, 0.20),
                    ]
                    for (nx, ny, nr) in blobs {
                        let jitter = (generator.next() - 0.5) * canvasSize.width * 0.05
                        let cx = canvasSize.width * nx + jitter
                        let cy = min(canvasSize.height * ny, baseY)
                        let r = canvasSize.width * nr
                        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.42)))
                    }
                }
                .blur(radius: size * 0.02)
            }
        case .autumn:
            // うろこ雲: 高い空に小さな雲が整列する
            ZStack {
                LinearGradient(
                    colors: [season.color.opacity(season.opacity), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                Canvas { context, canvasSize in
                    var generator = SeededRandom(seed: seed &+ 0xA07E)
                    for row in 0..<3 {
                        for column in 0..<4 {
                            let x = canvasSize.width * (0.18 + Double(column) * 0.22)
                                + (generator.next() - 0.5) * canvasSize.width * 0.04
                            let y = canvasSize.height * (0.20 + Double(row) * 0.11)
                            let w = canvasSize.width * 0.11
                            let h = canvasSize.height * 0.045
                            let rect = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
                            context.fill(
                                Path(ellipseIn: rect),
                                with: .color(.white.opacity(0.34 - Double(row) * 0.06))
                            )
                        }
                    }
                }
                .blur(radius: size * 0.012)
            }
        case .winter:
            // 凛と冴えた空: 縁が冷たく光り、中心に細い光条が伸びる
            ZStack {
                Circle()
                    .strokeBorder(season.color.opacity(season.opacity + 0.35), lineWidth: size * 0.09)
                    .blur(radius: size * 0.045)
                Canvas { context, canvasSize in
                    let center = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.44)
                    let arm = canvasSize.width * 0.30
                    var path = Path()
                    for angle in stride(from: 0.0, to: 360.0, by: 60.0) {
                        let radians = angle * .pi / 180
                        path.move(to: center)
                        path.addLine(to: CGPoint(
                            x: center.x + cos(radians) * arm,
                            y: center.y + sin(radians) * arm
                        ))
                    }
                    context.stroke(
                        path,
                        with: .color(.white.opacity(0.45)),
                        style: StrokeStyle(lineWidth: max(0.6, canvasSize.width * 0.016), lineCap: .round)
                    )
                }
                .blur(radius: size * 0.015)
            }
        }
    }

    @ViewBuilder
    private var weatherPattern: some View {
        switch orb.kind {
        case .rain, .drizzle, .thunderstorm:
            OrbCanvas(seed: seed, size: size) { context, generator in
                // 雨筋
                let count = orb.kind == .drizzle ? 4 : 6
                for _ in 0..<count {
                    let x = generator.next() * size
                    let y = generator.next() * size * 0.7
                    let length = size * (0.14 + generator.next() * 0.12)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + length * 0.25, y: y + length))
                    context.stroke(
                        path,
                        with: .color(.white.opacity(0.5 + generator.next() * 0.3)),
                        style: StrokeStyle(lineWidth: max(1, size * 0.03), lineCap: .round)
                    )
                }
                // 雷は紫の稲妻
                if orb.kind == .thunderstorm {
                    let originX = size * (0.35 + generator.next() * 0.3)
                    var bolt = Path()
                    bolt.move(to: CGPoint(x: originX, y: size * 0.30))
                    bolt.addLine(to: CGPoint(x: originX - size * 0.08, y: size * 0.52))
                    bolt.addLine(to: CGPoint(x: originX + size * 0.02, y: size * 0.52))
                    bolt.addLine(to: CGPoint(x: originX - size * 0.06, y: size * 0.74))
                    context.stroke(
                        bolt,
                        with: .color(Color(red: 1.0, green: 0.92, blue: 0.55).opacity(0.9)),
                        style: StrokeStyle(lineWidth: max(1, size * 0.035), lineCap: .round, lineJoin: .round)
                    )
                }
            }
        case .snow:
            OrbCanvas(seed: seed, size: size) { context, generator in
                for _ in 0..<8 {
                    let x = generator.next() * size
                    let y = size * 0.2 + generator.next() * size * 0.65
                    let radius = size * (0.03 + generator.next() * 0.035)
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.55 + generator.next() * 0.4)))
                }
            }
        case .fog:
            VStack(spacing: size * 0.09) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(height: size * 0.09)
                        .blur(radius: size * 0.045)
                        .padding(.horizontal, size * 0.12)
                }
            }
        case .cloudy, .partlyCloudy:
            // 玉に閉じ込められた綿雲
            Ellipse()
                .fill(Color.white.opacity(orb.kind == .cloudy ? 0.55 : 0.4))
                .frame(width: size * 0.55, height: size * 0.3)
                .blur(radius: size * 0.05)
                .offset(x: size * 0.05, y: size * 0.12)
        case .clear:
            // 澄んだ玉に小さなきらめき
            OrbCanvas(seed: seed, size: size) { context, generator in
                for _ in 0..<3 {
                    let x = size * 0.25 + generator.next() * size * 0.5
                    let y = size * 0.3 + generator.next() * size * 0.45
                    let radius = size * (0.02 + generator.next() * 0.02)
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.8)))
                }
            }
        }
    }
}

/// シード付き乱数で決定的に描く Canvas ヘルパー
private struct OrbCanvas: View {
    let seed: UInt64
    let size: CGFloat
    let draw: (inout GraphicsContext, inout SeededRandom) -> Void

    var body: some View {
        Canvas { context, _ in
            var generator = SeededRandom(seed: seed)
            var ctx = context
            draw(&ctx, &generator)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 空玉クリスタル(節目の日だけの特別版)

/// 雷雨の日・連続記録の節目・空玉ずかんコンプリートの日は、
/// 丸いガラス玉ではなく多面体のクリスタルとして表示される。
/// Apple 純正アプリには存在しない、そらだま独自のレアリティ表現。
struct CrystalOrbView: View {
    let orb: DailyOrb
    var size: CGFloat = 44
    /// false のとき TimelineView を使わず固定の輝きで描く(ImageRenderer・ウィジェット用)
    var animated: Bool = true

    private var palette: [Color] {
        switch orb.kind {
        case .thunderstorm:
            return [Color(red: 0.55, green: 0.62, blue: 1.0), Color(red: 0.72, green: 0.42, blue: 0.98), Color(red: 1.0, green: 0.60, blue: 0.30)]
        case .snow:
            return [Color(red: 0.70, green: 0.88, blue: 1.0), Color(red: 0.55, green: 0.68, blue: 1.0), Color(red: 1.0, green: 0.80, blue: 0.55)]
        default:
            return [Color(red: 0.40, green: 0.65, blue: 1.0), Color(red: 0.62, green: 0.42, blue: 0.98), Color(red: 1.0, green: 0.62, blue: 0.28)]
        }
    }

    private var seed: UInt64 { stableSeed(for: orb.dateKey) }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 15)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                crystalBody(pulse: (sin(time * 1.1) + 1) / 2)
            }
        } else {
            crystalBody(pulse: 0.65)
        }
    }

    private func crystalBody(pulse: Double) -> some View {
        ZStack {
            aura(pulse: pulse)
            CrystalFacetSparkles(seed: seed, palette: palette, pulse: pulse)
                .frame(width: size * 1.5, height: size * 1.5)
            gem(pulse: pulse)
            core(pulse: pulse)
        }
        .frame(width: size, height: size)
    }

    private func aura(pulse: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [palette[1].opacity(0.45 + pulse * 0.15), .clear],
                    center: .center, startRadius: 0, endRadius: size * 0.62
                )
            )
            .blendMode(.screen)
    }

    private func gem(pulse: Double) -> some View {
        let fill = LinearGradient(colors: palette, startPoint: .top, endPoint: .bottom)
        let facetStroke = Color.white.opacity(0.4)
        let rimStroke = Color.white.opacity(0.7)
        let shadowColor = palette[2].opacity(0.7)
        let shadowRadius = size * 0.10 + pulse * size * 0.04

        return CrystalGemShape()
            .fill(fill)
            .overlay(CrystalFacetLines().stroke(facetStroke, lineWidth: max(0.6, size * 0.012)))
            .overlay(CrystalGemShape().stroke(rimStroke, lineWidth: max(0.8, size * 0.02)))
            .frame(width: size * 0.62, height: size * 0.86)
            .shadow(color: shadowColor, radius: shadowRadius)
    }

    private func core(pulse: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.white, palette[2].opacity(0.85), .clear],
                    center: .center, startRadius: 0, endRadius: size * 0.13
                )
            )
            .frame(width: size * 0.20, height: size * 0.20)
            .opacity(0.75 + pulse * 0.25)
    }
}

/// 宝石カットのような、上下に尖った六角形の輪郭。
private struct CrystalGemShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        let points = [
            CGPoint(x: w * 0.5, y: 0),
            CGPoint(x: w, y: h * 0.30),
            CGPoint(x: w, y: h * 0.74),
            CGPoint(x: w * 0.5, y: h),
            CGPoint(x: 0, y: h * 0.74),
            CGPoint(x: 0, y: h * 0.30),
        ]
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

/// クリスタル本体の内側に、中心から各頂点へ伸びるカット面の筋を描く。
private struct CrystalFacetLines: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let center = CGPoint(x: w * 0.5, y: h * 0.42)
        let points = [
            CGPoint(x: w * 0.5, y: 0),
            CGPoint(x: w, y: h * 0.30),
            CGPoint(x: w, y: h * 0.74),
            CGPoint(x: w * 0.5, y: h),
            CGPoint(x: 0, y: h * 0.74),
            CGPoint(x: 0, y: h * 0.30),
        ]
        var path = Path()
        for point in points {
            path.move(to: center)
            path.addLine(to: point)
        }
        return path
    }
}

/// クリスタルの左右に浮かぶ小さな光の粒(参考画像のフランキング・スパークル)。
private struct CrystalFacetSparkles: View {
    let seed: UInt64
    let palette: [Color]
    let pulse: Double

    var body: some View {
        Canvas { context, size in
            var generator = SeededRandom(seed: seed &+ 0x9E37)
            let positions: [(CGFloat, CGFloat)] = [(0.06, 0.5), (0.94, 0.5), (0.5, 0.97)]
            for (nx, ny) in positions {
                let jitter = (generator.next() - 0.5) * 6
                let x = size.width * nx
                let y = size.height * ny + jitter
                let radius: CGFloat = 2.2 + CGFloat(pulse) * 1.4
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(palette[0].opacity(0.55 + pulse * 0.35)))
            }
        }
        .allowsHitTesting(false)
    }
}

