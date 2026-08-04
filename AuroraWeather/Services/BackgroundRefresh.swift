import Foundation
import BackgroundTasks
import WidgetKit

/// バックグラウンドで天気を取り直し、通知の予約を入れ替える仕組み。
///
/// 以前は「アプリを開いたときにだけ通知を予約する」実装だったため、
/// 数日アプリを開かないと雨の通知も朝の傘予報も完全に止まっていた。
/// iOS が許すタイミングで定期的に起こしてもらい、予報の更新に追随させる。
enum BackgroundRefresh {
    static let taskIdentifier = "com.tkiyo1007.soradama.refresh"

    /// アプリ起動時に一度だけ呼ぶ。
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task)
        }
    }

    /// 次回の実行を予約する。iOS が実際の実行時刻を決めるので、あくまで希望。
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // 早すぎる要求は無視されるため、最短でも3時間後にする
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // 次回ぶんを先に予約しておく(ここで予約しないと二度と起きない)
        schedule()

        let work = Task {
            await refreshAndReschedule()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// 現在地(= ウィジェットと共有している地点)の天気を取り直して通知を組み直す。
    static func refreshAndReschedule() async {
        let defaults = UserDefaults.standard
        let rainEnabled = defaults.bool(forKey: "aurora.rainAlerts")
        let morningEnabled = defaults.bool(forKey: "aurora.morningAlerts")
        guard rainEnabled || morningEnabled else { return }

        let place = SharedStore.lastPlace()
        guard let bundle = try? await WeatherService().fetch(
            latitude: place.latitude,
            longitude: place.longitude
        ) else { return }

        let notifications = NotificationService()
        if rainEnabled {
            notifications.scheduleRainAlert(for: bundle, placeName: place.name)
        }
        if morningEnabled {
            notifications.scheduleMorningUmbrella(for: bundle, placeName: place.name)
        }
        // 取れたてのデータでウィジェットも更新しておく
        WidgetCenter.shared.reloadAllTimelines()
    }
}
