import SwiftUI
import WidgetKit

/// 「今日の空玉」Widget の案内を、必要な利用者に一度だけ出すための判定。
/// WidgetKit の取得に失敗した場合は、設置済みの利用者へ誤って案内しないよう表示を見送る。
enum TodayOrbWidgetDiscovery {
    static let widgetKind = "TodayOrbWidget"
    static let dismissedKey = "soradama.todayOrbWidgetGuide.dismissed"

    static func shouldShow(
        hasOrb: Bool,
        installationState: Bool?,
        isDismissed: Bool
    ) -> Bool {
        hasOrb && installationState == false && !isDismissed
    }

    /// WidgetKitへの確認が重なったとき、最後に始めた確認結果だけを画面へ反映する。
    static func isCurrent(resultGeneration: Int, currentGeneration: Int) -> Bool {
        resultGeneration == currentGeneration
    }

    static func installationState() async -> Bool? {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                switch result {
                case .success(let widgets):
                    continuation.resume(returning: widgets.contains { $0.kind == widgetKind })
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// 端末の週の開始曜日に合わせて、月表示用の日付と先頭の空欄を組み立てる。
enum OrbCalendarLayout {
    static func monthDays(for displayedMonth: Date, calendar: Calendar) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayCount = calendar.range(of: .day, in: .month, for: displayedMonth)?.count else {
            return []
        }

        let weekdayOfFirstDay = calendar.component(.weekday, from: interval.start)
        let leadingEmptyDays = (weekdayOfFirstDay - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leadingEmptyDays)
        for offset in 0..<dayCount {
            days.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        return days
    }
}

/// 詳細の共有画像を作り直す条件。別の日の玉に切り替えたときに加え、
/// 開いたまま日付が変わる・前面復帰で期間が終わるなど季節の飾りの有無が変わったときも作り直し、
/// 画面の見た目と共有される画像を一致させる。
struct OrbShareImageKey: Hashable {
    let dateKey: String
    let isHalloween: Bool

    init(orb: DailyOrb, seasonal: SeasonalContext) {
        dateKey = orb.dateKey
        isHalloween = seasonal.decorates(orb)
    }
}

// MARK: - 空玉コレクション画面

struct OrbCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.seasonalContext) private var seasonal
    @AppStorage(TodayOrbWidgetDiscovery.dismissedKey) private var isWidgetGuideDismissed = false
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
    /// 「今日の空玉」Widget の設置状態。nil は確認前または確認失敗。
    @State private var todayOrbWidgetInstalled: Bool?
    @State private var widgetInstallationCheckGeneration = 0
    @State private var showWidgetGuide = false

    private let store = OrbStore.shared

    /// `initialSelectedOrb` を渡すと、その玉の詳細(共有ボタン付き)を開いた状態で表示する。
    /// 天気画面の「今日の空玉」から、記録した玉を見て共有するまでを1タップにするため。
    init(initialSelectedOrb: DailyOrb? = nil) {
        _selectedOrb = State(initialValue: initialSelectedOrb)
    }

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
                        OrbRecordingGuide(initiallyExpanded: store.orbs.isEmpty) {
                            dismiss()
                        }
                        weekdayHeader
                        orbGrid
                        statsRow
                        if TodayOrbWidgetDiscovery.shouldShow(
                            hasOrb: !store.orbs.isEmpty,
                            installationState: todayOrbWidgetInstalled,
                            isDismissed: isWidgetGuideDismissed
                        ) {
                            widgetDiscoveryCard
                        }
                        zukanSection
                            .padding(.top, 20)
                        WeatherAttributionFooter()
                            .tint(Color(red: 0.72, green: 0.86, blue: 1.0))
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
        .sheet(isPresented: $showWidgetGuide) {
            NavigationStack {
                WidgetGuideView(showsCloseButton: true)
            }
        }
        .task {
            await refreshWidgetInstallationState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !isWidgetGuideDismissed else { return }
            Task { await refreshWidgetInstallationState() }
        }
    }

    // MARK: Widget 案内

    private var widgetDiscoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Color(red: 0.70, green: 0.84, blue: 1.0))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ホーム画面に空玉を飾る")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("アプリを開かないときも、今日の空玉と連続日数をひと目で見られます。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    consumeWidgetDiscoveryCard()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ウィジェットの案内を閉じる")
            }

            Button {
                consumeWidgetDiscoveryCard()
                showWidgetGuide = true
            } label: {
                Label("追加方法を見る", systemImage: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.13), Color(red: 0.43, green: 0.55, blue: 0.90).opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func consumeWidgetDiscoveryCard() {
        Haptics.selection()
        withAnimation(.easeOut(duration: 0.2)) {
            isWidgetGuideDismissed = true
        }
    }

    @MainActor
    private func refreshWidgetInstallationState() async {
        widgetInstallationCheckGeneration &+= 1
        let generation = widgetInstallationCheckGeneration
        let state = await TodayOrbWidgetDiscovery.installationState()
        guard TodayOrbWidgetDiscovery.isCurrent(
            resultGeneration: generation,
            currentGeneration: widgetInstallationCheckGeneration
        ) else { return }
        todayOrbWidgetInstalled = state
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
                    .frame(width: 44, height: 44)
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
                    .frame(width: 44, height: 44)
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
        // 7列の密集表示はAXサイズの文字を物理的に収められない。
        // 日付の完全な情報は各玉のVoiceOverラベルに残し、視覚上の重なりだけを防ぐ。
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// 表示月の日付一覧(週頭合わせの nil パディング付き)
    private var monthDays: [Date?] {
        OrbCalendarLayout.monthDays(for: displayedMonth, calendar: calendar)
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
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
                        .halloweenOrbAccent(seasonal.decorates(orb), size: 38)
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
        let entries = SkyVariant.zukanEntries
        let total = entries.count
        // 朝焼け・夕暮れは下の「季節の空」で扱うため、16マスの進捗には含めない。
        // 全時間帯を数えると 18/16 のような不正な表示になる。
        let completed = SkyVariant.zukanCollectedCount(in: collected)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("空玉ずかん")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(completed)/\(total) コンプリート")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
                ForEach(entries) { variant in
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
                                // 日本語の「夜のくもり」は1行で収まるが、英語の
                                // "Thunderstorm at night" は省略されてしまう。
                                // 2行まで許し、縮小率も広げて語尾が切れないようにする。
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .multilineTextAlignment(.center)
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
                        Text(has ? time.skyLabel : String(localized: "？？？"))
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
                subject: Text(SoradamaShareContent.subject),
                message: Text(SoradamaShareContent.messageWithStoreLink),
                preview: SharePreview("空玉コレクション", image: image)
            ) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("今月の空を共有")
        } else {
            // 画像生成が終わるまでの一瞬だけプレースホルダ
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(.white.opacity(0.4))
                .accessibilityHidden(true)
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
            Text(String(localized: "\(Self.monthTitleFormatter.string(from: displayedMonth))の空"))
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
                    .halloweenOrbAccent(seasonal.decorates(orb), size: 130)
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
                            subject: Text(SoradamaShareContent.subject),
                            message: Text(SoradamaShareContent.messageWithStoreLink),
                            preview: SharePreview("\(orb.dateKey)の空玉", image: image)
                        ) {
                            Label("共有", systemImage: "square.and.arrow.up")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 9)
                                .background(Color.white.opacity(0.15), in: Capsule())
                        }
                        .accessibilityLabel(Self.singleOrbShareAccessibilityLabel(for: orb))
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
        .task(id: OrbShareImageKey(orb: orb, seasonal: seasonal)) {
            orbShareImage = nil
            let renderer = ImageRenderer(
                content: singleOrbShareCard(orb, isHalloween: seasonal.decorates(orb))
            )
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
    private func singleOrbShareCard(_ orb: DailyOrb, isHalloween: Bool) -> some View {
        VStack(spacing: 12) {
            OrbView(orb: orb, size: 120, animated: false)
                .halloweenOrbAccent(isHalloween, size: 120)
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

    static func singleOrbShareAccessibilityLabel(
        for orb: DailyOrb,
        locale: Locale = .current
    ) -> String {
        let date = orb.date?.formatted(
            .dateTime.locale(locale).year().month().day()
        ) ?? orb.dateKey
        return String(localized: "\(date)の空玉を共有")
    }
}

/// iOS 17 ではアプリから直接 Widget を追加できないため、OS標準の安全な手順を案内する。
/// コレクションからは一度限りのカードで、設定からはいつでも開ける。
struct WidgetGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .caption) private var stepBadgeSize: CGFloat = 28

    let showsCloseButton: Bool

    init(showsCloseButton: Bool = false) {
        self.showsCloseButton = showsCloseButton
    }

    private let previewOrb = DailyOrb(
        dateKey: "widget-guide",
        kind: .partlyCloudy,
        tempMax: 24,
        tempMin: 16,
        humidity: 55,
        precipProbability: nil,
        placeName: ""
    )

    private var steps: [LocalizedStringKey] {
        [
            "ホーム画面の何もない場所を長押しします",
            "「編集」または「＋」から「ウィジェットを追加」を選びます",
            "「空玉」を検索し、「今日の空玉」を追加します",
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                widgetPreview

                Text("アプリを開かないときも、今日の空玉と連続日数をひと目で見られます。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)

                VStack(spacing: 14) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text(verbatim: "\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: stepBadgeSize, height: stepBadgeSize)
                                .background(
                                    Color(red: 0.16, green: 0.30, blue: 0.58),
                                    in: Circle()
                                )
                            Text(step)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 3)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Label(
                    "追加後にウィジェットをタップすると、空玉コレクションが開きます。",
                    systemImage: "hand.tap"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(20)
        }
        .navigationTitle("ウィジェットを追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var widgetPreview: some View {
        VStack(spacing: 7) {
            OrbView(orb: previewOrb, size: 76, animated: false)
            Text("今日の空玉")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 150, height: 150)
        .background(
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.09, blue: 0.22), Color(red: 0.16, green: 0.15, blue: 0.36)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .accessibilityHidden(true)
    }
}

#Preview {
    OrbCollectionView()
}
