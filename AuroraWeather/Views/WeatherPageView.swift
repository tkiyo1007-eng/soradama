import SwiftUI

/// 1つの地点の天気を表示するページ(スワイプページングの1枚)
struct WeatherPageView: View {
    let place: SavedPlace
    let viewModel: WeatherViewModel
    let onOpenCollection: () -> Void

    @State private var scrollOffset: CGFloat = 0
    @State private var showRadar = false
    /// 最初の1回は説明を厚くし、価値が伝わった後は天気情報を押し下げない高さにする。
    @AppStorage("soradama.todayOrbCard.hasOpened") private var hasOpenedTodayOrbCard = false
    /// カード類を下から順番に登場させる演出用のフラグ
    @State private var cardsAppeared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.seasonalContext) private var seasonal

    private var collapseProgress: Double {
        (Double(-scrollOffset) / 140).clamped(to: 0...1)
    }

    init(
        place: SavedPlace,
        viewModel: WeatherViewModel,
        onOpenCollection: @escaping () -> Void = {}
    ) {
        self.place = place
        self.viewModel = viewModel
        self.onOpenCollection = onOpenCollection
    }

    var body: some View {
        Group {
            if let weather = viewModel.bundles[place.id] {
                content(weather)
            } else if viewModel.errors[place.id] != nil {
                ErrorStateView(message: viewModel.errors[place.id] ?? "") {
                    Task { await viewModel.ensureLoaded(place.id, force: true) }
                }
            } else {
                LoadingStateView()
            }
        }
        .sheet(isPresented: $showRadar) {
            RadarSheet(place: place, timeZone: viewModel.bundles[place.id]?.timeZone ?? .current)
        }
    }

    private func content(_ weather: WeatherBundle) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PageScrollOffsetKey.self,
                        value: proxy.frame(in: .named("weatherScroll")).minY
                    )
                }
                .frame(height: 0)

                CurrentHeaderView(
                    placeName: place.name,
                    isCurrentLocation: place.isCurrentLocation,
                    weather: weather,
                    degrees: viewModel.degrees,
                    collapseProgress: collapseProgress
                )
                .padding(.top, 54)

                if viewModel.errors[place.id] != nil {
                    OfflineBanner(fetchedAt: weather.fetchedAt, timeZone: weather.timeZone)
                        .padding(.horizontal, 16)
                }

                Group {
                    if let orb = OrbStore.shared.orb(for: Date()),
                       TodayOrbCardPolicy.shouldShow(
                           pageID: place.id,
                           primaryPageID: viewModel.pages.first?.id,
                           hasTodayOrb: true
                       ) {
                        TodayOrbCard(
                            orb: orb,
                            streak: OrbStore.shared.streak,
                            isExpanded: !hasOpenedTodayOrbCard,
                            decoration: seasonal.decoration(for: orb)
                        ) {
                            hasOpenedTodayOrbCard = true
                            onOpenCollection()
                        }
                        .revealed(cardsAppeared, order: 0, reduceMotion: reduceMotion)
                    } else if let event = seasonal.event,
                              place.id == viewModel.pages.first?.id,
                              !viewModel.loadingIDs.contains(place.id) {
                        // 期間中でも、今日の玉が無い(通信失敗・保存済みの天気だけ)日は
                        // 記録済みと見せず、記録される条件と取り直し方だけを案内する。
                        SeasonalRecordHint(event: event)
                            .revealed(cardsAppeared, order: 0, reduceMotion: reduceMotion)
                    }

                    HourlyForecastCard(weather: weather, degrees: viewModel.degrees)
                        .revealed(cardsAppeared, order: 1, reduceMotion: reduceMotion)

                    DetailsGrid(weather: weather, degrees: viewModel.degrees, units: viewModel.units)
                        .revealed(cardsAppeared, order: 2, reduceMotion: reduceMotion)

                    // 気象庁の高解像度レーダーは日本周辺限定。
                    // 海外で利用できない機能を主要導線として見せない。
                    if RadarService.isCovered(latitude: place.latitude, longitude: place.longitude) {
                        RadarCardButton { showRadar = true }
                            .revealed(cardsAppeared, order: 3, reduceMotion: reduceMotion)
                    }

                    TemperatureChartCard(weather: weather, units: viewModel.units)
                        .revealed(cardsAppeared, order: 4, reduceMotion: reduceMotion)
                    DailyForecastCard(weather: weather, degrees: viewModel.degrees)
                        .revealed(cardsAppeared, order: 5, reduceMotion: reduceMotion)

                    VStack(spacing: 3) {
                        Text("最終更新: \(weather.fetchedAt.timeLabel(in: weather.timeZone))")
                        WeatherAttributionFooter()
                            .foregroundStyle(Color(red: 0.72, green: 0.86, blue: 1.0))
                            .tint(Color(red: 0.72, green: 0.86, blue: 1.0))
                        if RadarService.isCovered(latitude: place.latitude, longitude: place.longitude) {
                            Link("雨雲レーダー: 気象庁", destination: DataAttribution.jmaRadar)
                                .tint(Color(red: 0.72, green: 0.86, blue: 1.0))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .revealed(cardsAppeared, order: 6, reduceMotion: reduceMotion)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 30)
        }
        .coordinateSpace(name: "weatherScroll")
        .onPreferenceChange(PageScrollOffsetKey.self) { value in
            scrollOffset = value
        }
        .refreshable {
            Haptics.soft()
            await viewModel.ensureLoaded(place.id, force: true)
        }
        .onAppear {
            guard !cardsAppeared else { return }
            if reduceMotion {
                cardsAppeared = true
            } else {
                // ヘッダーの気温が立ち上がった直後にカードが続くよう、少し遅らせる
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    cardsAppeared = true
                }
            }
        }
    }
}

// MARK: - 今日の空玉

/// 天気の確認画面にも「空を集める」という空玉ならではの価値を残すカード。
/// 初回だけ少し詳しく伝え、開いた後はコンパクトにして予報の閲覧を妨げない。
struct TodayOrbCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let orb: DailyOrb
    let streak: Int
    let isExpanded: Bool
    /// 開催中の今日の玉だけ、その行事。期間の一言と控えめな光を添える。
    var decoration: SeasonalEvent? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(
                alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center,
                spacing: 14
            ) {
                OrbView(
                    orb: orb,
                    size: orbSize
                )
                    .seasonalOrbAccent(decoration, size: orbSize)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: isExpanded ? 5 : 3) {
                    Text("今日の空玉")
                        .font(isExpanded ? .headline : .subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    HStack(spacing: 5) {
                        Text(orb.kind.label)
                        Text(verbatim: "·")
                            .accessibilityHidden(true)
                        Text(orb.timeOfDay.skyLabel)
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))

                    Text(streak > 1
                         ? String(localized: "\(streak)日連続で集めています")
                         : String(localized: "最初の空を集めました"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(red: 0.72, green: 0.86, blue: 1.0))

                    if let decoration {
                        Text(decoration.cardLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(decoration.textColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isExpanded {
                        Label("タップして今日の空玉を見る・共有する", systemImage: "square.and.arrow.up")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 6)

                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(isExpanded ? 16 : 13)
            .background(
                decoration?.cardBackground
                    ?? LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.20, blue: 0.42).opacity(0.92),
                            Color(red: 0.12, green: 0.16, blue: 0.34).opacity(0.92),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        decoration?.cardStroke ?? Color.white.opacity(0.15),
                        lineWidth: decoration == nil ? 0.8 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("今日の空玉を開きます。共有もできます")
    }

    private var orbSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 50 : (isExpanded ? 68 : 50)
    }
}

// MARK: - 登場アニメーション

private extension View {
    /// カードを下からふわっと登場させる。`order` の順に少し遅れて現れることで、
    /// 画面を開いたときに一枚ずつ積み上がるような印象になる。
    func revealed(_ isVisible: Bool, order: Int, reduceMotion: Bool = false) -> some View {
        // 「動きを減らす」設定ではスライドインもフェードもさせない
        opacity(isVisible || reduceMotion ? 1 : 0)
            .offset(y: (isVisible || reduceMotion) ? 0 : 18)
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.5, dampingFraction: 0.85)
                        .delay(Double(order) * 0.06),
                value: isVisible
            )
    }
}

private struct PageScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - オフラインバナー

struct OfflineBanner: View {
    let fetchedAt: Date
    let timeZone: TimeZone

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption)
            Text("通信できないため \(fetchedAt.timeLabel(in: timeZone)) 時点の情報を表示中")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.45), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 雨雲レーダーへの導線カード

struct RadarCardButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard(title: "雨雲レーダー", systemImage: "cloud.rain") {
                HStack {
                    Text("周辺の雨雲の動きと1時間先の予測を見る")
                        .font(.callout)
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("雨雲レーダーを開く")
    }
}

// MARK: - ローディング / エラー状態

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            WeatherIconView(kind: .partlyCloudy, isDay: true)
                .frame(width: 56, height: 56)
            Text("天気を取得しています…")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(.largeTitle))
                .imageScale(.large)
                .foregroundStyle(.white.opacity(0.9))
            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: retry) {
                Text("再試行")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
