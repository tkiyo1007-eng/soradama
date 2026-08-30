import SwiftUI

@main
struct SoradamaWatchApp: App {
    init() {
        WatchSyncService.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchWeatherView()
        }
    }
}
