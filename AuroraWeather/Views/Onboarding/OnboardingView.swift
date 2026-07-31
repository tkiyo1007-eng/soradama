import SwiftUI

/// 初回起動時にアプリの世界観(空を集める)を3枚で伝えるオンボーディング。
/// 最後の「はじめる」を押してから位置情報の許可を求めることで、
/// 何のための許可なのかが伝わった状態でシステムダイアログが出る。
struct OnboardingView: View {
    /// 「はじめる」タップ時に呼ばれる(位置情報の許可と初回読み込みを開始する)
    let onFinish: () -> Void

    @State private var page = 0

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
                        title: "空玉(そらだま)へようこそ",
                        message: "その日の空を、小さなガラス玉に\n閉じ込める天気アプリです"
                    )
                    .tag(0)

                    pageView(
                        orbKind: .rain,
                        title: "毎日ひとつ、空がたまる",
                        message: "アプリを開いた日の空が玉になって残ります。\n晴れも雨も、集めると宝物になります"
                    )
                    .tag(1)

                    pageView(
                        orbKind: .snow,
                        title: "あなたの空を教えてください",
                        message: "現在地の天気を表示するために\n位置情報を使います(あとから変更できます)"
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button {
                    if page < 2 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page < 2 ? "つぎへ" : "はじめる")
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.10, green: 0.12, blue: 0.28))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.white, in: Capsule())
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
    }

    private func pageView(orbKind: WeatherKind, title: String, message: String) -> some View {
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
    OnboardingView(onFinish: {})
}
