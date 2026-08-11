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
    /// ずかんでタップされたマス
    @State private var selectedVariant: SkyVariant?
    /// 月の振り返りカードを開いているか
    @State private var showMonthSummary = false

    private let store = OrbStore.shared

    /// 設定で選ばれた気温の単位(摂氏/華氏)に合わせて表示する
    private static func degrees(_ celsius: Double) -> String {
        "\(Int(SharedStore.units().convert(celsius).rounded()))°"
    }
    private let calendar = Calendar.current

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        // 書式ごとロケールに委ねる(日本語 "2026年8月" / 英語 "August 2026")
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
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
                } else if let variant = selectedVariant {
                    variantDetail(variant)
                }
            }
            .sheet(isPresented: $showMonthSummary) {
                if let summary = store.summary(forMonthOf: displayedMonth) {
                    MonthSummaryView(summary: summary, orbs: store.orbs(inMonthOf: displayedMonth))
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

    /// 曜日の頭文字。ハードコードしていたため英語版でも「日 月 火…」と出ていた。
    /// カレンダーから取れば言語も、週の始まり(日曜/月曜)も端末に合う。
    private static var weekdaySymbols: [String] {
        var calendar = Calendar.current
        calendar.locale = .current
        let symbols = calendar.veryShortWeekdaySymbols
        // firstWeekday は 1 = 日曜。地域によっては月曜始まりなので回転させる
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { _, day in
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
                .font(.caption2)
                .foregroundStyle(.white.opacity(isFuture ? 0.25 : 0.6))
        }
        .frame(height: 52)
    }

    // MARK: 統計

    private var statsRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statCard(value: "\(store.count(inMonthOf: displayedMonth))", label: "今月の空玉")
                statCard(value: "\(store.streak)", label: "連続日数")
            }
            // その月に玉が1つでもあれば、振り返りカードを開ける
            if store.summary(forMonthOf: displayedMonth) != nil {
                Button {
                    Haptics.selection()
                    showMonthSummary = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles.rectangle.stack")
                        Text("この月をふりかえる")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .opacity(0.6)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }

    private func statCard(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded).weight(.bold))
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

    /// 図鑑表示用の代表的な玉(実際に記録された日付に関わらず、一定の見た目にする)
    private func archetype(for variant: SkyVariant, season: Season = .spring) -> DailyOrb {
        // 季節の質感を出すため、その季節の中央あたりの日付キーを使う
        let month = ["spring": "04", "summer": "07", "autumn": "10", "winter": "01"][season.rawValue] ?? "04"
        return DailyOrb(
            dateKey: "2000-\(month)-15",
            kind: variant.kind,
            tempMax: 22,
            tempMin: 16,
            humidity: 55,
            precipProbability: nil,
            placeName: "",
            timeOfDay: variant.timeOfDay
        )
    }

    private var zukanSection: some View {
        let collected = store.collectedSkies
        let total = SkyVariant.zukanEntries.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("空玉ずかん")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(collected.count)/\(total) コンプリート")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
                ForEach(SkyVariant.zukanEntries) { variant in
                    let has = collected.contains(variant)
                    Button {
                        guard has else { return }
                        Haptics.selection()
                        selectedVariant = variant
                    } label: {
                        VStack(spacing: 5) {
                            if has {
                                OrbView(orb: archetype(for: variant), size: 46, showsSeason: false)
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
                            Text(has ? variant.label : "？？？")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(has ? 0.7 : 0.35))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!has)
                }
            }
            Text("同じ天気でも、昼と夜では別の玉になります")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))

            Divider().overlay(Color.white.opacity(0.15))

            seasonRow
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// 季節の空とマジックアワーの収集状況
    private var seasonRow: some View {
        let seasons = store.collectedSeasons
        let magic = Set(store.orbs.values.map(\.timeOfDay))
        return VStack(alignment: .leading, spacing: 10) {
            Text("季節の空")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            HStack(spacing: 10) {
                ForEach(Season.allCases, id: \.self) { season in
                    let has = seasons.contains(season)
                    VStack(spacing: 4) {
                        if has {
                            OrbView(orb: archetype(for: SkyVariant(kind: .clear, timeOfDay: .day), season: season), size: 40)
                        } else {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .frame(width: 40, height: 40)
                        }
                        Text(has ? season.skyName : season.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(has ? 0.7 : 0.3))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 8) {
                ForEach([TimeOfDay.dawn, TimeOfDay.dusk], id: \.self) { time in
                    let has = magic.contains(time)
                    HStack(spacing: 6) {
                        if has {
                            OrbView(orb: archetype(for: SkyVariant(kind: .clear, timeOfDay: time)), size: 26, showsSeason: false)
                        } else {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                .frame(width: 26, height: 26)
                        }
                        Text(has ? "\(time.label)の空" : "？？？")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(has ? 0.7 : 0.3))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("日の出・日の入りの前後1時間に開くと、特別な空が残ります")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
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
                        Text(date.formatted(.dateTime.locale(Locale.current).year().month().day().weekday()))
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

                // その日が節気・満月なら、それを主役として見せる
                if let term = orb.solarTerm {
                    VStack(spacing: 2) {
                        Text(term.label)
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundStyle(Color(red: term.accent.r, green: term.accent.g, blue: term.accent.b))
                        Text(term.poem)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                } else if let phase = orb.moonPhase, phase != .newMoon {
                    Text(phase.label)
                        .font(.system(.subheadline, design: .serif).weight(.medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.95, blue: 0.8))
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

    /// ずかんのマスをタップしたときの詳細(初めて出会った日と収集数)
    private func variantDetail(_ variant: SkyVariant) -> some View {
        let first = store.firstOrb(of: variant)
        let count = store.count(of: variant)
        return ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { selectedVariant = nil }

            VStack(spacing: 12) {
                OrbView(orb: archetype(for: variant), size: 110, showsSeason: false)
                    .padding(.top, 6)
                Text(variant.label)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let first, let date = first.date {
                    Text("はじめて出会った日")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(date.formatted(.dateTime.locale(Locale.current).year().month().day()))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Text("これまでに \(count) 個")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                Button("閉じる") { selectedVariant = nil }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.15), in: Capsule())
                    .padding(.top, 2)
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
            .padding(.horizontal, 52)
        }
    }

    /// 1日ぶんの空玉をSNSに貼れる縦型カード
    private func singleOrbShareCard(_ orb: DailyOrb) -> some View {
        VStack(spacing: 12) {
            OrbView(orb: orb, size: 120, animated: false)
                .padding(.top, 6)
            if let date = orb.date {
                Text(date.formatted(.dateTime.locale(Locale.current).year().month().day().weekday()))
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
