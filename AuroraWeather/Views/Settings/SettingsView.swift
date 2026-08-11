import SwiftUI
import StoreKit

/// アプリの設定画面。
/// 以前は雨の通知トグルが都市検索シートの中に埋もれていて見つけにくく、
/// 気温の単位切り替えに至っては UI 自体が無かったため、独立した画面に集約した。
struct SettingsView: View {
    @Bindable var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var showTipJar = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(selection: Binding(
                        get: { viewModel.units },
                        set: { viewModel.setUnits($0) }
                    )) {
                        ForEach(UnitSystem.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    } label: {
                        Label("単位", systemImage: "thermometer.medium")
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("表示")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { viewModel.rainAlertsEnabled },
                        set: { newValue in Task { await viewModel.setRainAlerts(newValue) } }
                    )) {
                        Label("雨が近づいたら通知", systemImage: "umbrella")
                    }
                    Toggle(isOn: Binding(
                        get: { viewModel.morningAlertsEnabled },
                        set: { newValue in Task { await viewModel.setMorningAlerts(newValue) } }
                    )) {
                        Label("朝7時の傘予報", systemImage: "sunrise")
                    }
                    Toggle(isOn: Binding(
                        get: { viewModel.streakRemindersEnabled },
                        set: { newValue in Task { await viewModel.setStreakReminders(newValue) } }
                    )) {
                        Label("空玉の連続記録リマインド", systemImage: "flame")
                    }
                } header: {
                    Text("通知")
                } footer: {
                    Text("雨の通知は降り出しの約30分前(降水確率50%以上)、傘予報は毎朝7時、リマインドは連続3日以上の記録が途切れそうな夜8時に届きます。アプリを開いていない間もバックグラウンドで予報を取り直し、最新の内容に合わせて通知します。")
                }

                Section {
                    Button {
                        requestReview()
                    } label: {
                        Label("レビューを書く", systemImage: "star")
                    }
                    ShareLink(item: URL(string: "https://apps.apple.com/app/id6788443049")!) {
                        Label("友だちに教える", systemImage: "square.and.arrow.up")
                    }
                    if TipJar.isEnabled {
                        Button {
                            showTipJar = true
                        } label: {
                            Label("作者を応援する", systemImage: "heart")
                        }
                    }
                } header: {
                    Text("応援")
                } footer: {
                    if TipJar.isEnabled {
                        Text("応援は任意です。払わなくても、すべての機能をそのまま使えます。")
                    }
                }

                Section {
                    LabeledContent("バージョン", value: Self.appVersion)
                    Link(destination: URL(string: "https://tkiyo1007-eng.github.io/soradama/privacy.html")!) {
                        Label("プライバシーポリシー", systemImage: "hand.raised")
                    }
                } header: {
                    Text("このアプリについて")
                } footer: {
                    Text("天気データ: Open-Meteo.com\n雨雲レーダー: 出典 気象庁ホームページ（高解像度降水ナウキャスト）\nhttps://www.jma.go.jp/bosai/nowc/")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showTipJar) {
                TipJarView()
            }
        }
    }

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        return version
    }
}
