import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var viewModel = WeatherViewModel()
    @State private var showSearch = false
    @State private var showOrbCollection = false
    @State private var showWallpaper = false
    @State private var showSettings = false
    @State private var orbBounce = false
    /// 今日の空玉が記録された瞬間のお祝いトースト(通常の日)
    @State private var orbToast: OrbRecordResult?
    /// 節気・満月・連続記録の節目だけに出す、画面いっぱいのお祝い
    @State private var celebration: OrbRecordResult?

    var body: some View {
        ZStack {
            SkyBackground(
                kind: viewModel.currentKind,
                isDay: viewModel.currentIsDay,
                sunrise: viewModel.currentBundle?.sunrise,
                sunset: viewModel.currentBundle?.sunset
            )

            TabView(selection: Bindable(viewModel).selectionID) {
                ForEach(viewModel.pages) { place in
                    WeatherPageView(place: place, viewModel: viewModel)
                        .tag(place.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: viewModel.pages.count > 1 ? .automatic : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .never))

            topBar

            if let toast = orbToast {
                orbToastView(toast)
            }

            if let celebration, let orb = OrbStore.shared.orb(for: Date()) {
                OrbCelebrationView(orb: orb, event: celebration) {
                    withAnimation(.easeOut(duration: 0.35)) { self.celebration = nil }
                    showOrbCollection = true
                }
                .transition(.opacity)
                .zIndex(20)
            }

            if !hasSeenOnboarding {
                OnboardingView {
                    withAnimation(.easeOut(duration: 0.4)) { hasSeenOnboarding = true }
                    // ここではじめて位置情報の許可 → 初回読み込み → 最初の空玉の記録が走る
                    Task { await viewModel.loadInitial() }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .sheet(isPresented: $showSearch) {
            CitySearchView(viewModel: viewModel)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showOrbCollection) {
            OrbCollectionView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showWallpaper) {
            if let bundle = viewModel.currentBundle, let place = viewModel.pages.first(where: { $0.id == viewModel.selectionID }) {
                WallpaperExportView(
                    placeName: place.name,
                    weather: bundle,
                    degrees: viewModel.degrees,
                    orb: OrbStore.shared.orb(for: Date())
                )
            }
        }
        .task {
            // 初回はオンボーディングの「はじめる」後に読み込む
            // (何の説明もなく位置情報ダイアログを出さないため)
            if hasSeenOnboarding {
                await viewModel.loadInitial()
            }
        }
        .onChange(of: viewModel.selectionID) { _, newID in
            Haptics.selection()
            Task { await viewModel.ensureLoaded(newID) }
        }
        .onChange(of: scenePhase) { _, phase in
            // 一晩置いて開き直したときなどに古い予報が残らないよう、
            // 前面復帰のたびに再取得を試みる(30分以内ならensureLoadedが弾く)
            if phase == .active {
                Task { await viewModel.ensureLoaded(viewModel.selectionID) }
            }
        }
        .onOpenURL { url in
            // 「今日の空玉」ウィジェットのタップでコレクションを直接開く
            if url.scheme == "soradama", url.host == "collection" {
                showOrbCollection = true
            }
        }
        .onChange(of: viewModel.lastOrbEvent) { _, event in
            guard let event else { return }
            Haptics.success()
            // 節気・満月・連続記録の節目は画面いっぱいのお祝い、それ以外はトースト。
            // 毎日派手に出すと特別さが薄れるので、ここで出し分ける
            let isSpecial = event.solarTerm != nil || event.isFullMoon || event.isMilestone
            if isSpecial {
                withAnimation(.easeIn(duration: 0.3)) { celebration = event }
            } else {
                withAnimation(.spring(duration: 0.5)) { orbToast = event }
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation(.easeOut(duration: 0.4)) {
                        if orbToast == event { orbToast = nil }
                    }
                }
            }
        }
    }

    private var topBar: some View {
        VStack {
            HStack {
                Button {
                    Haptics.selection()
                    guard !reduceMotion else {
                        showOrbCollection = true
                        return
                    }
                    withAnimation(.interpolatingSpring(stiffness: 320, damping: 8)) {
                        orbBounce = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeOut(duration: 0.2)) { orbBounce = false }
                        showOrbCollection = true
                    }
                } label: {
                    MiniOrbIcon()
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                        .scaleEffect(orbBounce ? 1.35 : 1.0)
                        .overlay(alignment: .topTrailing) {
                            // 連続日数バッジ。数字が見えているだけで「途切れさせたくない」動機になる
                            let streak = OrbStore.shared.streak
                            if streak > 1 {
                                Text("\(streak)")
                                    .font(.system(.caption2, design: .rounded).weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        Color(red: 1.0, green: 0.55, blue: 0.30),
                                        in: Capsule()
                                    )
                                    .offset(x: 6, y: -4)
                            }
                        }
                }
                .accessibilityLabel("空玉コレクションを開く。連続\(OrbStore.shared.streak)日")

                Spacer()

                if viewModel.currentBundle != nil {
                    Button {
                        Haptics.selection()
                        showWallpaper = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("今日の空を壁紙として保存")
                }

                Button {
                    Haptics.selection()
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("都市を検索")

                Button {
                    Haptics.selection()
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("設定")
            }
            .padding(.horizontal, 16)
            Spacer()
        }
    }

    /// 今日の空玉が生まれた瞬間のお祝い表示。
    /// 玉ができたことに気づけるようにし、コレクションへの導線も兼ねる。
    private func orbToastView(_ event: OrbRecordResult) -> some View {
        VStack {
            Spacer()
            Button {
                orbToast = nil
                showOrbCollection = true
            } label: {
                HStack(spacing: 10) {
                    if let orb = OrbStore.shared.orb(for: Date()) {
                        OrbView(orb: orb, size: 34)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(toastTitle(event))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(event.streak > 1 ? "\(event.streak)日連続で集めています" : "タップしてコレクションを見る")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 30)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func toastTitle(_ event: OrbRecordResult) -> String {
        if event.isMilestone { return String(localized: "特別な空玉クリスタルが生まれました！") }
        if event.isNewKind { return String(localized: "新しい種類の空玉をずかんに追加！") }
        return String(localized: "今日の空玉ができました")
    }
}

/// トップバー用の小さなガラス玉アイコン。
/// ゆっくり明滅・膨張することで「生きている」印象を与える(呼吸の演出)。
private struct MiniOrbIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
            let breath = reduceMotion
                ? 0.5
                : (sin(timeline.date.timeIntervalSinceReferenceDate * 1.15) + 1) / 2

            ZStack {
                // 呼吸に合わせて外側へ広がるやわらかな光
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.55, green: 0.80, blue: 1.0).opacity(0.35 * breath), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 16
                        )
                    )
                    .frame(width: 34, height: 34)
                    .blendMode(.screen)

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.35, green: 0.65, blue: 0.98), Color(red: 0.22, green: 0.30, blue: 0.72)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.65 + 0.3 * breath), .clear],
                                center: UnitPoint(x: 0.32, y: 0.25),
                                startRadius: 0,
                                endRadius: 8
                            )
                        )
                    Circle()
                        .strokeBorder(Color.white.opacity(0.45 + 0.25 * breath), lineWidth: 0.8)
                }
                .frame(width: 22, height: 22)
                .scaleEffect(1 + 0.05 * breath)
            }
            .frame(width: 34, height: 34)
        }
    }
}

#Preview {
    ContentView()
}
