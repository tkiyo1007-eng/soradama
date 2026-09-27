import SwiftUI

/// 記録処理は変えず、WeatherViewModel.ensureLoaded / OrbStore.recordToday の条件を伝える。
/// 記録がない初回だけ展開し、普段のカレンダー閲覧を妨げない。
struct OrbRecordingGuide: View {
    @State private var isExpanded: Bool
    let returnToWeather: () -> Void

    init(initiallyExpanded: Bool, returnToWeather: @escaping () -> Void) {
        _isExpanded = State(initialValue: initiallyExpanded)
        self.returnToWeather = returnToWeather
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                Text("「自分の空」に設定した地点が対象です。別の都市を見るだけでは、記録する地点は変わりません。")
                Text("端末の日付で1日1個。同じ日に天気を取り直すと、その日の空玉が更新されます。")
                Text("通信に失敗したときや、保存済みの天気を表示するだけでは、新しい空玉は記録されません。自分の空の天気画面を下に引くと、もう一度取得できます。")
                Text("カレンダーの玉をタップすると、その日の空を確認できます。玉がある月は「この月をふりかえる」からまとめを見られます。")
                Button(action: returnToWeather) {
                    Text("天気に戻る")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityHint("コレクションを閉じて天気画面に戻ります")
            }
            .font(.callout)
            .foregroundStyle(.white.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("空玉はいつ残る？")
                    .font(.subheadline.weight(.semibold))
                Text("アプリで自分の空の天気を取得できたとき、自動で記録されます。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44, alignment: .leading)
        }
        .multilineTextAlignment(.leading)
        .tint(Color(red: 0.72, green: 0.86, blue: 1.0))
        .padding(14)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}
