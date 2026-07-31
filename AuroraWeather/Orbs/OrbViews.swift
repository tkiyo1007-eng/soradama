import SwiftUI

// MARK: - 空玉コレクション画面

struct OrbCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayedMonth = Date()
    @State private var selectedOrb: DailyOrb?
    /// ImageRenderer は重いので、body評価のたびに実行せず月が変わったときだけ作り直す
    @State private var monthShareImage: Image?
    /// 詳細モーダルで開いている玉の共有画像(玉を選び直したら作り直す)
    @State private var orbShareImage: Image?

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
            monthShareImage = nil // 月が変わったので共有画像を作り直す
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

    @ViewBuilder
    private var shareButton: some View {
        if let image = monthShareImage {
            ShareLink(
                item: image,
                preview: SharePreview("空玉コレクション", image: image)
            ) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.white)
            }
        } else {
            // 画像生成が終わるまでの一瞬だけプレースホルダ
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(.white.opacity(0.4))
                .task(id: DailyOrb.key(for: displayedMonth)) { renderMonthShareImage() }
        }
    }

    private func renderMonthShareImage() {
        let renderer = ImageRenderer(content: shareCard)
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            monthShareImage = Image(uiImage: uiImage)
        }
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
                        OrbView(orb: orb, size: 34, animated: false)
                    } else {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: 34, height: 34)
                    }
                }
            }
            VStack(spacing: 2) {
                Text("空玉 — 空を集める天気アプリ")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                Text("apps.apple.com/app/id6788443049")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }
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
                    HStack(spacing: 10) {
                        Label("\(Int(orb.humidity))%", systemImage: "humidity")
                        if let probability = orb.precipProbability {
                            Label("\(Int(probability))%", systemImage: "umbrella")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 2)
                }

                Text("「\(OrbVoice.line(for: orb))」")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    if let image = orbShareImage {
                        ShareLink(
                            item: image,
                            preview: SharePreview("\(orb.dateKey)の空玉", image: image)
                        ) {
                            Label("共有", systemImage: "square.and.arrow.up")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 9)
                                .background(Color.white.opacity(0.15), in: Capsule())
                        }
                    }
                    Button("閉じる") { selectedOrb = nil }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.15), in: Capsule())
                }
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
        .task(id: orb.dateKey) {
            orbShareImage = nil
            let renderer = ImageRenderer(content: singleOrbShareCard(orb))
            renderer.scale = 3
            if let uiImage = renderer.uiImage {
                orbShareImage = Image(uiImage: uiImage)
            }
        }
    }

    /// 1日ぶんの空玉をSNSに貼れる縦型カード
    private func singleOrbShareCard(_ orb: DailyOrb) -> some View {
        VStack(spacing: 12) {
            OrbView(orb: orb, size: 120, animated: false)
                .padding(.top, 6)
            if let date = orb.date {
                Text(date.formatted(.dateTime.locale(Locale(identifier: "ja_JP")).year().month().day().weekday()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Text("\(orb.placeName)・\(orb.kind.label)  最高\(Self.degrees(orb.tempMax))/最低\(Self.degrees(orb.tempMin))")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
            Text("「\(OrbVoice.line(for: orb))」")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            VStack(spacing: 2) {
                Text("空玉 — 空を集める天気アプリ")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                Text("apps.apple.com/app/id6788443049")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.top, 2)
        }
        .padding(26)
        .background(
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.09, blue: 0.22), Color(red: 0.16, green: 0.15, blue: 0.36)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

#Preview {
    OrbCollectionView()
}
