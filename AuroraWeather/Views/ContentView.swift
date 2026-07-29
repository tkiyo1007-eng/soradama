import SwiftUI

struct ContentView: View {
    @State private var viewModel = WeatherViewModel()
    @State private var showSearch = false
    @State private var showOrbCollection = false
    @State private var showWallpaper = false
    @State private var showSettings = false
    @State private var orbBounce = false

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
            await viewModel.loadInitial()
        }
        .onChange(of: viewModel.selectionID) { _, newID in
            Haptics.selection()
            Task { await viewModel.ensureLoaded(newID) }
        }
    }

    private var topBar: some View {
        VStack {
            HStack {
                Button {
                    Haptics.selection()
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
                }
                .accessibilityLabel("空玉コレクションを開く")

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
