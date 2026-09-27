import SwiftUI

/// データ処理や通信を行わず、既存の提供元と利用条件への導線だけを表示する。
struct DataAttributionView: View {
    var body: some View {
        List {
            Section("天気と地点データ") {
                Link("天気データ: Open-Meteo", destination: DataAttribution.openMeteo)
                Link("都市情報: Open-Meteo", destination: DataAttribution.geocoding)
                Link("地点データ: GeoNames", destination: DataAttribution.geoNames)
                Link("ライセンス: CC BY 4.0", destination: DataAttribution.creativeCommons)
                Link("Open-Meteoの利用条件", destination: DataAttribution.openMeteoLicence)
            }
            Section("雨雲レーダー（日本周辺）") {
                Link("雨雲レーダー: 気象庁", destination: DataAttribution.jmaRadar)
                Link("気象庁の利用規約", destination: DataAttribution.jmaTerms)
                Text("気象庁の高解像度降水ナウキャストを地図に重ねて表示しています。")
                    .foregroundStyle(.secondary)
            }
            Section("アプリ内での加工") {
                Text("空玉では提供データを単位換算し、グラフ・各種指標・空玉として表示しています。提供元による推奨を示すものではありません。")
            }
        }
        // A sheet inherits the presenting footer's caption font and muted color.
        // Give the full details page its own readable text environment.
        .font(.body)
        .foregroundStyle(.primary)
        .tint(.accentColor)
        .navigationTitle("データの出典と利用条件")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 初回設定中も、コレクションからも出典を確認できる共通の末尾表示。
struct WeatherAttributionFooter: View {
    var showsCitySource = false
    @State private var showsDetails = false

    var body: some View {
        VStack(spacing: 2) {
            if showsCitySource {
                sourceLink("都市情報: Open-Meteo", destination: DataAttribution.geocoding)
                sourceLink("地点データ: GeoNames", destination: DataAttribution.geoNames)
            } else {
                sourceLink("天気データ: Open-Meteo", destination: DataAttribution.openMeteo)
            }
            sourceLink("ライセンス: CC BY 4.0", destination: DataAttribution.creativeCommons)
            Button("データの出典と利用条件") { showsDetails = true }
                .frame(minHeight: 44)
        }
        .font(.caption)
        .buttonStyle(.borderless)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showsDetails) {
            NavigationStack {
                DataAttributionView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("閉じる") { showsDetails = false }
                        }
                    }
            }
            .font(.body)
            .foregroundStyle(.primary)
            .tint(.accentColor)
        }
    }

    private func sourceLink(_ title: LocalizedStringKey, destination: URL) -> some View {
        Link(destination: destination) {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
    }
}
