import SwiftUI

@main
struct AuroraWeatherApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // バックグラウンド更新の受け口を登録する(起動時に一度だけ)
        BackgroundRefresh.register()
        // App GroupだけではiPhoneとWatchの端末間同期はできないため、
        // WatchConnectivityを起動して最新のホーム地点と単位を渡す。
        PhoneWatchSyncService.shared.activate()
        PhoneWatchSyncService.shared.sync(
            place: SharedStore.lastPlace(),
            units: SharedStore.units()
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            // 背面に回るたびに次回の更新を予約し直す
            if phase == .background {
                BackgroundRefresh.schedule()
            }
        }
    }
}
