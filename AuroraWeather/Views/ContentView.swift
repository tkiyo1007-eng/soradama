import SwiftUI

struct ContentView: View {
    @State private var viewModel = WeatherViewModel()
    @State private var showSearch = false
    @State private var showOrbCollection = false

    var body: some View {
        ZStack {
            SkyBackground(
                kind: viewModel.currentKind,
                isDay: viewModel.currentIsDay
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
                    showOrbCollection = true
                } label: {
                    MiniOrbIcon()
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("空玉コレクションを開く")

                Spacer()

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
            }
            .padding(.horizontal, 16)
            Spacer()
        }
    }
}

/// トップバー用の小さなガラス玉アイコン
private struct MiniOrbIcon: View {
    var body: some View {
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
                        colors: [.white.opacity(0.8), .clear],
                        center: UnitPoint(x: 0.32, y: 0.25),
                        startRadius: 0,
                        endRadius: 8
                    )
                )
            Circle()
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8)
        }
        .frame(width: 22, height: 22)
    }
}

#Preview {
    ContentView()
}
