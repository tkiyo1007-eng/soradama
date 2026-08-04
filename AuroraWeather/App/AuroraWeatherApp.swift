import SwiftUI

@main
struct AuroraWeatherApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // バックグラウンド更新の受け口を登録する(起動時に一度だけ)
        BackgroundRefresh.register()
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
