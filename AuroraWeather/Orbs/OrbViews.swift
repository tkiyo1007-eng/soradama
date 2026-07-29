import SwiftUI

// MARK: - 空玉の描画

/// その日の天気が閉じ込められたガラス玉。
/// 天気の種類×気温×日付シードから、同じ日は常に同じ、日が違えば少し違う模様になる。
struct OrbView: View {
    let orb: DailyOrb
    var size: CGFloat = 44

    private var baseColors: [Color] {
        orb.kind.skyColors(isDay: true)
    }

    /// 気温による色味(暑い日は暖色、寒い日は氷色のにじみ)
    private var temperatureTint: Color? {
        if orb.tempMax >= 30 { return Color(red: 1.0, green: 0.55, blue: 0.30) }
        if orb.tempMax >= 25 { return Color(red: 1.0, green: 0.80, blue: 0.45) }
        if orb.tempMax < 5 { return Color(red: 0.60, green: 0.85, blue: 1.0) }
        return nil
    }

    private var seed: UInt64 {
        stableSeed(for: orb.dateKey)
    }

    var body: some View {
        Group {
            if orb.isMilestone {
                CrystalOrbView(orb: orb, size: size)
            } else {
                regularOrb
            }
        }
        .accessibilityLabel(orb.isMilestone
            ? "\(orb.dateKey)の特別な空玉クリスタル、\(orb.kind.label)"
            : "\(orb.dateKey)の空玉、\(orb.kind.label)")
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

            // 天気の模様
            weatherPattern
                .clipShape(Circle())

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
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let pulse = (sin(time * 1.1) + 1) / 2

            ZStack {
                aura(pulse: pulse)
                CrystalFacetSparkles(seed: seed, palette: palette, pulse: pulse)
                    .frame(width: size * 1.5, height: size * 1.5)
                gem(pulse: pulse)
                core(pulse: pulse)
            }
            .frame(width: size, height: size)
        }
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

// MARK: - 空玉コレクション画面

struct OrbCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayedMonth = Date()
    @State private var selectedOrb: DailyOrb?

    private let store = OrbStore.shared

    /// 設定で選ばれた気温の単位(摂氏/華氏)に合わせて表示する
    private static func degrees(_ celsius: Double) -> String {
        "\(Int(SharedStore.units().convert(celsius).rounded()))°"
    }
    private let calendar = Calendar.current

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.07, green: 0.09, blue: 0.22), Color(red: 0.16, green: 0.15, blue: 0.36)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        monthHeader
                        weekdayHeader
                        orbGrid
                        statsRow
                        Text("アプリを開いた日の空が、玉になって残ります")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.top, 6)
                        zukanSection
                            .padding(.top, 20)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("空玉コレクション")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    shareButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                if let orb = selectedOrb {
                    orbDetail(orb)
                }
            }
        }
    }

    // MARK: 月ナビゲーション

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            Spacer()
            Text(Self.monthTitleFormatter.string(from: displayedMonth))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canGoForward ? .white.opacity(0.85) : .white.opacity(0.25))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .disabled(!canGoForward)
        }
    }

    private var canGoForward: Bool {
        !calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    private func shiftMonth(by value: Int) {
        if let shifted = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = shifted
        }
    }

    // MARK: グリッド

    private var weekdayHeader: some View {
        HStack {
            ForEach(["日", "月", "火", "水", "木", "金", "土"], id: \.self) { day in
                Text(day)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// 表示月の日付一覧(週頭合わせの nil パディング付き)
    private var monthDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayCount = calendar.range(of: .day, in: .month, for: displayedMonth)?.count else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start) // 1 = 日曜
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for offset in 0..<dayCount {
            days.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        return days
    }

    private var orbGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 12) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    daySlot(day)
                } else {
                    Color.clear.frame(height: 52)
                }
            }
        }
    }

    @ViewBuilder
    private func daySlot(_ day: Date) -> some View {
        let dayNumber = calendar.component(.day, from: day)
        let isFuture = day > Date()
        VStack(spacing: 3) {
            if let orb = store.orb(for: day) {
                Button {
                    Haptics.selection()
                    selectedOrb = orb
                } label: {
                    OrbView(orb: orb, size: 38)
                }
                .buttonStyle(.plain)
            } else {
                Circle()
                    .strokeBorder(
                        Color.white.opacity(isFuture ? 0.06 : 0.18),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                    .frame(width: 38, height: 38)
            }
            Text("\(dayNumber)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(isFuture ? 0.25 : 0.6))
        }
        .frame(height: 52)
    }

    // MARK: 統計

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(value: "\(store.count(inMonthOf: displayedMonth))", label: "今月の空玉")
            statCard(value: "\(store.streak)", label: "連続日数")
        }
        .padding(.top, 6)
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: 空玉ずかん

    private var collectedKinds: Set<WeatherKind> {
        Set(store.orbs.values.map(\.kind))
    }

    /// 図鑑表示用の代表的な玉(実際に記録された日付に関わらず、種類ごとに一定の見た目にする)
    private func archetype(for kind: WeatherKind) -> DailyOrb {
        DailyOrb(
            dateKey: "archetype-\(kind.rawValue)",
            kind: kind,
            tempMax: 22,
            tempMin: 16,
            humidity: 55,
            precipProbability: nil,
            placeName: ""
        )
    }

    private var zukanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("空玉ずかん")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(collectedKinds.count)/\(WeatherKind.allCases.count) コンプリート")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
                ForEach(WeatherKind.allCases, id: \.self) { kind in
                    VStack(spacing: 5) {
                        if collectedKinds.contains(kind) {
                            OrbView(orb: archetype(for: kind), size: 46)
                        } else {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.06))
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                Image(systemName: "questionmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            .frame(width: 46, height: 46)
                        }
                        Text(collectedKinds.contains(kind) ? kind.label : "？？？")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(collectedKinds.contains(kind) ? 0.7 : 0.35))
                    }
                }
            }
            Text("天気を体験すると、その玉が図鑑に加わります")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: 共有

    private var shareButton: some View {
        ShareLink(
            item: shareImage,
            preview: SharePreview("空玉コレクション", image: shareImage)
        ) {
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(.white)
        }
    }

    private var shareImage: Image {
        let renderer = ImageRenderer(content: shareCard)
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "circle")
    }

    /// X などに貼れる共有用カード
    private var shareCard: some View {
        VStack(spacing: 14) {
            Text(Self.monthTitleFormatter.string(from: displayedMonth) + "の空")
                .font(.headline)
                .foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 7), spacing: 10) {
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                    if let day, let orb = store.orb(for: day) {
                        OrbView(orb: orb, size: 34)
                    } else {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: 34, height: 34)
                    }
                }
            }
            Text("空玉 — 空を集める天気アプリ")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.09, blue: 0.22), Color(red: 0.16, green: 0.15, blue: 0.36)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: 詳細表示

    private func orbDetail(_ orb: DailyOrb) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { selectedOrb = nil }

            VStack(spacing: 14) {
                OrbView(orb: orb, size: 130)
                    .padding(.top, 8)
                VStack(spacing: 4) {
                    if let date = orb.date {
                        Text(date.formatted(.dateTime.locale(Locale(identifier: "ja_JP")).year().month().day().weekday()))
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    Text("\(orb.placeName)・\(orb.kind.label)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    Text("最高 \(Self.degrees(orb.tempMax)) / 最低 \(Self.degrees(orb.tempMin))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Button("閉じる") { selectedOrb = nil }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.15), in: Capsule())
                    .padding(.bottom, 8)
            }
            .padding(22)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.10, green: 0.12, blue: 0.28), Color(red: 0.18, green: 0.17, blue: 0.40)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .padding(.horizontal, 44)
        }
    }
}

#Preview {
    OrbCollectionView()
}
