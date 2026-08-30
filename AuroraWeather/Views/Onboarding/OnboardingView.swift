import SwiftUI

/// 初回起動時にアプリの世界観(空を集める)を3枚で伝えるオンボーディング。
/// 最後に「現在地」か「都市」を明示的に選んでもらい、ホーム地点が
/// 確定した場合だけオンボーディングを完了する。
struct OnboardingView: View {
    @Bindable var viewModel: WeatherViewModel
    /// ホーム地点が確定したときだけ呼ばれる。
    let onFinish: () -> Void

    @State private var page = 0
    @State private var isLocating = false
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

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    pageView(
                        orbKind: .clear,
                        title: "今日の天気が、空玉になる",
                        message: "天気を確認した日の空が、その日だけの\nガラス玉として残ります"
                    )
                    .tag(0)

                    pageView(
                        orbKind: .rain,
                        title: "集めて、ホーム画面にも飾れる",
                        message: "毎日の空をカレンダーで振り返り、\n今日の空玉をウィジェットで楽しめます"
                    )
                    .tag(1)

                    pageView(
                        orbKind: .snow,
                        title: "あなたの空を教えてください",
                        message: "現在地を使うか、都市を選んで\nあなたの空を決められます(あとから変更できます)"
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                if page < 2 {
                    Button {
                        withAnimation { page += 1 }
                    } label: {
                        Text("つぎへ")
                            .font(.headline)
                            .foregroundStyle(Color(red: 0.10, green: 0.12, blue: 0.28))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.white, in: Capsule())
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                } else {
                    locationChoices
                        .padding(.horizontal, 32)
                        .padding(.bottom, 28)
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
                .foregroundStyle(Color(red: 0.10, green: 0.12, blue: 0.28))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.white, in: Capsule())
            }
            .disabled(isLocating)

            Button {
                didChooseCity = false
                isChoosingCity = true
            } label: {
                Label("都市を選ぶ", systemImage: "building.2")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(.white.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1))
            }
            .disabled(isLocating)

            Text("位置情報は現在地の天気だけに使います。許可しなくても都市を選んで使えます")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    private func chooseCurrentLocation() {
        guard !isLocating else { return }
        isLocating = true
        Task {
            let succeeded = await viewModel.useCurrentLocation()
            isLocating = false
            if succeeded {
                onFinish()
            }
        }
    }

    private func finishAfterCitySelection() {
        guard didChooseCity else { return }
        didChooseCity = false
        onFinish()
    }

    private func pageView(orbKind: WeatherKind, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        VStack(spacing: 22) {
            Spacer()
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
                size: 150
            )
            .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

#Preview {
    OnboardingView(viewModel: WeatherViewModel(), onFinish: {})
}
