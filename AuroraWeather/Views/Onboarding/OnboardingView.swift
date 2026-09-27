import SwiftUI

/// 初回起動時にアプリの世界観(空を集める)を3枚で伝えるオンボーディング。
/// 最後に「現在地」か「都市」を明示的に選んでもらい、ホーム地点が
/// 確定した場合だけオンボーディングを完了する。
struct OnboardingView: View {
    @Bindable var viewModel: WeatherViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// ホーム地点が確定したときだけ呼ばれる。
    let onFinish: () -> Void

    @State private var page = 0
    @State private var isLocating = false
    @State private var locationSelectionTask: Task<Void, Never>?
    @State private var isChoosingCity = false
    @State private var didChooseCity = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.09, blue: 0.22), Color(red: 0.16, green: 0.15, blue: 0.36)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GeometryReader { geometry in
                // PageTabViewは子の自然な高さまで伸びないため、文字が大きい場合や
                // 高さが足りない画面では、選択中の案内を直接スクロール領域に載せる。
                if dynamicTypeSize.isAccessibilitySize || geometry.size.height < 650 {
                    ScrollViewReader { reader in
                        ScrollView {
                            VStack(spacing: 24) {
                                introduction(for: page, scrollable: true)
                                    .id("onboarding-top")
                                Text("\(page + 1) / 3")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                                pageActions(showBack: true)
                            }
                            .padding(.vertical, 24)
                        }
                        .onChange(of: page) { _, _ in
                            reader.scrollTo("onboarding-top", anchor: .top)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        TabView(selection: $page) {
                            ForEach(0..<3) { index in
                                introduction(for: index, scrollable: false)
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        pageActions(showBack: false)
                            .padding(.bottom, 28)
                    }
                }
            }
        }
        .sheet(isPresented: $isChoosingCity, onDismiss: finishAfterCitySelection) {
            CitySearchView(viewModel: viewModel, purpose: .choosePrimary) {
                // 閉じる/スワイプでキャンセルした場合はここを通らない。
                didChooseCity = true
            }
            .presentationDetents([.large])
        }
        .onDisappear {
            locationSelectionTask?.cancel()
            locationSelectionTask = nil
            isLocating = false
        }
    }

    @ViewBuilder
    private func introduction(for index: Int, scrollable: Bool) -> some View {
        switch index {
        case 0:
            pageView(
                orbKind: .clear,
                title: "天気を取得できた日が、空玉になる",
                message: "「自分の空」の天気を取得できたとき、端末の日付で1日1個の空玉が残ります",
                scrollable: scrollable
            )
        case 1:
            pageView(
                orbKind: .rain,
                title: "集めて、ホーム画面にも飾れる",
                message: "毎日の空をカレンダーで振り返り、\n今日の空玉をウィジェットで楽しめます",
                scrollable: scrollable
            )
        default:
            pageView(
                orbKind: .snow,
                title: "あなたの空を教えてください",
                message: "現在地を使うか、都市を選んで\nあなたの空を決められます(あとから変更できます)",
                scrollable: scrollable
            )
        }
    }

    private func pageActions(showBack: Bool) -> some View {
        VStack(spacing: 16) {
            if page < 2 {
                Button(action: advancePage) {
                    Text("つぎへ")
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.10, green: 0.12, blue: 0.28))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.white, in: Capsule())
                }
                .accessibilityIdentifier("onboarding.next")
            } else {
                locationChoices
            }
            if showBack && page > 0 {
                Button { page -= 1 } label: {
                    Text("戻る")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(isLocating)
                .accessibilityIdentifier("onboarding.back")
            }
        }
        .padding(.horizontal, 32)
    }

    private var locationChoices: some View {
        VStack(spacing: 12) {
            if let message = viewModel.locationSelectionError {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(message)
            }

            Button {
                chooseCurrentLocation()
            } label: {
                HStack(spacing: 8) {
                    if isLocating {
                        ProgressView()
                            .tint(Color(red: 0.10, green: 0.12, blue: 0.28))
                    } else {
                        Image(systemName: "location.fill")
                    }
                    Text(isLocating ? String(localized: "現在地を取得しています…") : String(localized: "現在地を使う"))
                }
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color(red: 0.10, green: 0.12, blue: 0.28))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.white, in: Capsule())
            }
            .disabled(isLocating)
            .accessibilityIdentifier("onboarding.currentLocation")

            Button {
                didChooseCity = false
                isChoosingCity = true
            } label: {
                Label("都市を選ぶ", systemImage: "building.2")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(.white.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1))
            }
            .disabled(isLocating)
            .accessibilityIdentifier("onboarding.city")

            Text("位置情報は現在地の天気と地点名の取得に使います。許可しなくても都市を選んで使えます")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chooseCurrentLocation() {
        guard !isLocating else { return }
        isLocating = true
        locationSelectionTask = Task {
            let succeeded = await viewModel.useCurrentLocation()
            guard !Task.isCancelled else { return }
            locationSelectionTask = nil
            isLocating = false
            if succeeded {
                onFinish()
            }
        }
    }

    private func advancePage() {
        if reduceMotion {
            page += 1
        } else {
            withAnimation { page += 1 }
        }
    }

    private func finishAfterCitySelection() {
        guard didChooseCity else { return }
        didChooseCity = false
        onFinish()
    }

    private func pageView(orbKind: WeatherKind, title: LocalizedStringKey, message: LocalizedStringKey, scrollable: Bool) -> some View {
        VStack(spacing: 22) {
            if !scrollable { Spacer(minLength: 16) }
            OrbView(
                orb: DailyOrb(
                    dateKey: "onboarding-\(orbKind.rawValue)",
                    kind: orbKind,
                    tempMax: 22,
                    tempMin: 15,
                    humidity: 50,
                    precipProbability: nil,
                    placeName: ""
                ),
                size: scrollable ? 100 : 150
            )
            .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding.title")
            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.message")
            if !scrollable { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 28)
    }
}

#Preview {
    OnboardingView(viewModel: WeatherViewModel(), onFinish: {})
}
