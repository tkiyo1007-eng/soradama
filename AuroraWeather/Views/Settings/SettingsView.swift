import SwiftUI
import WidgetKit

/// アプリの設定画面。
/// 以前は雨の通知トグルが都市検索シートの中に埋もれていて見つけにくく、
/// 気温の単位切り替えに至っては UI 自体が無かったため、独立した画面に集約した。
struct SettingsView: View {
    @Bindable var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showTipJar = false
    @State private var showBackupExporter = false
    @State private var showBackupImporter = false
    @State private var backupDocument = OrbBackupDocument()
    @State private var backupResultMessage: String?
    @State private var pendingBackupData: Data?
    @State private var pendingBackupPreview: OrbBackupImportResult?
    @State private var pendingBackupRevision: UInt64?
    @State private var showRestoreConfirmation = false
    @State private var isReconfirmingChangedCollection = false

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
                    NavigationLink {
                        WidgetGuideView()
                    } label: {
                        Label("ホーム画面に空玉を飾る", systemImage: "rectangle.stack.badge.plus")
                    }
                } header: {
                    Text("ウィジェット")
                } footer: {
                    Text("今日の空玉と連続日数を、ホーム画面でいつでも見られます。")
                }

                Section {
                    Button {
                        prepareBackupExport()
                    } label: {
                        Label("空玉をバックアップ", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showBackupImporter = true
                    } label: {
                        Label("バックアップから復元", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("コレクション")
                } footer: {
                    Text("集めた空玉をJSONファイルに保存できます。復元では、今ある空玉を消さずにバックアップを追加・更新します。")
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
                    Link(destination: AppStoreLinks.writeReview) {
                        Label("レビューを書く", systemImage: "star")
                    }
                    ShareLink(
                        item: AppStoreLinks.app,
                        subject: Text(SoradamaShareContent.subject),
                        message: Text(SoradamaShareContent.message)
                    ) {
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
                    Link(destination: Self.privacyURL) {
                        Label("プライバシーポリシー", systemImage: "hand.raised")
                    }
                    NavigationLink {
                        DataAttributionView()
                    } label: {
                        Label("データの出典と利用条件", systemImage: "info.circle")
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
            .fileExporter(
                isPresented: $showBackupExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: Self.backupFilename
            ) { result in
                switch result {
                case .success:
                    backupResultMessage = String(localized: "空玉のバックアップを書き出しました。")
                case let .failure(error):
                    if (error as? CocoaError)?.code != .userCancelled {
                        backupResultMessage = String(localized: "バックアップを書き出せませんでした。")
                    }
                }
            }
            .fileImporter(
                isPresented: $showBackupImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                importBackup(from: result)
            }
            .confirmationDialog(
                restoreConfirmationTitle,
                isPresented: $showRestoreConfirmation,
                titleVisibility: .visible
            ) {
                Button("追加・更新して復元", role: .destructive) {
                    completeBackupImport()
                }
                Button("キャンセル", role: .cancel) {
                    clearPendingBackup()
                }
            } message: {
                if let preview = pendingBackupPreview {
                    Text("追加 \(preview.insertedCount)個、更新 \(preview.replacedCount)個。今ある別の日の空玉は削除されません。")
                }
            }
            .alert(
                "空玉バックアップ",
                isPresented: Binding(
                    get: { backupResultMessage != nil },
                    set: { if !$0 { backupResultMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(backupResultMessage ?? "")
            }
        }
    }

    private func prepareBackupExport() {
        do {
            backupDocument = OrbBackupDocument(data: try OrbStore.shared.exportBackupData())
            showBackupExporter = true
        } catch {
            backupResultMessage = String(localized: "バックアップを作成できませんでした。")
        }
    }

    private func importBackup(from result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(error) = result,
               (error as? CocoaError)?.code != .userCancelled {
                backupResultMessage = String(localized: "バックアップを読み込めませんでした。")
            }
            return
        }

        Task {
            let readResult = await Task.detached(priority: .userInitiated) {
                Result<Data, Error> {
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard values.isRegularFile == true else {
                        throw CocoaError(.fileReadUnsupportedScheme)
                    }
                    if let fileSize = values.fileSize,
                       fileSize > OrbBackupCodec.maximumDataSize {
                        throw OrbBackupError.fileTooLarge
                    }
                    return try OrbBackupCodec.readData(from: url)
                }
            }.value

            do {
                let data = try readResult.get()
                let preview = try OrbStore.shared.previewBackupImport(data)
                guard preview.insertedCount > 0 || preview.replacedCount > 0 else {
                    backupResultMessage = String(localized: "復元する変更はありませんでした。")
                    return
                }
                pendingBackupData = data
                pendingBackupPreview = preview
                pendingBackupRevision = OrbStore.shared.revision
                isReconfirmingChangedCollection = false
                showRestoreConfirmation = true
            } catch {
                backupResultMessage = backupErrorMessage(for: error)
            }
        }
    }

    private func completeBackupImport() {
        guard let data = pendingBackupData else {
            clearPendingBackup()
            return
        }
        do {
            let imported = try OrbStore.shared.importBackupData(
                data,
                expectedRevision: pendingBackupRevision
            )
            WidgetCenter.shared.reloadAllTimelines()
            backupResultMessage = String(
                localized: "空玉を復元しました（追加: \(imported.insertedCount)個、更新: \(imported.replacedCount)個）。"
            )
            clearPendingBackup()
        } catch OrbBackupError.collectionChanged {
            do {
                let preview = try OrbStore.shared.previewBackupImport(data)
                guard preview.insertedCount > 0 || preview.replacedCount > 0 else {
                    backupResultMessage = String(localized: "復元する変更はありませんでした。")
                    clearPendingBackup()
                    return
                }
                pendingBackupPreview = preview
                pendingBackupRevision = OrbStore.shared.revision
                isReconfirmingChangedCollection = true
                showRestoreConfirmation = false
                Task { @MainActor in
                    await Task.yield()
                    showRestoreConfirmation = true
                }
            } catch {
                backupResultMessage = backupErrorMessage(for: error)
                clearPendingBackup()
            }
        } catch {
            backupResultMessage = backupErrorMessage(for: error)
            clearPendingBackup()
        }
    }

    private func clearPendingBackup() {
        pendingBackupData = nil
        pendingBackupPreview = nil
        pendingBackupRevision = nil
        isReconfirmingChangedCollection = false
        showRestoreConfirmation = false
    }

    private var restoreConfirmationTitle: LocalizedStringKey {
        isReconfirmingChangedCollection
            ? "復元内容をもう一度確認してください"
            : "バックアップを復元しますか？"
    }

    private func backupErrorMessage(for error: Error) -> String {
        switch error {
        case OrbBackupError.fileTooLarge:
            return String(localized: "バックアップのファイルサイズが大きすぎます。")
        case OrbBackupError.unsupportedSchemaVersion:
            return String(localized: "このバージョンでは読み込めないバックアップです。")
        case OrbBackupError.tooManyOrbs,
             OrbBackupError.inconsistentDateKey,
             OrbBackupError.invalidOrbData:
            return String(localized: "バックアップの内容が正しくありません。")
        case OrbBackupError.persistenceFailed:
            return String(localized: "バックアップを保存できませんでした。")
        default:
            return String(localized: "バックアップを読み込めませんでした。")
        }
    }

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        return version
    }

    private static var backupFilename: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Soradama-Orbs-\(formatter.string(from: Date()))"
    }

    private static var privacyURL: URL {
        let filename = Locale.current.language.languageCode?.identifier == "ja"
            ? "privacy.html"
            : "privacy-en.html"
        return URL(string: "https://tkiyo1007-eng.github.io/soradama/\(filename)")!
    }
}
