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
        UInt64(bitPattern: Int64(orb.dateKey.hashValue))
    }

    var body: some View {
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
        .accessibilityLabel("\(orb.dateKey)の空玉、\(orb.kind.label)")
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

// MARK: - 空玉コレクション画面

struct OrbCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayedMonth = Date()
    @State private var selectedOrb: DailyOrb?

    private let store = OrbStore.shared
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
                    Text("最高 \(Int(orb.tempMax.rounded()))° / 最低 \(Int(orb.tempMin.rounded()))°")
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
