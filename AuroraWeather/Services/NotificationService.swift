import Foundation
import UserNotifications

/// 雨の降り始めをローカル通知で知らせるサービス。
/// アプリが天気を取得したタイミングで、12時間以内の降水を検出して予約する。
struct NotificationService {
    static let rainAlertID = "soradama.rainAlert"

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound])
        return granted ?? false
    }

    /// 12時間以内に降水確率50%以上の時間帯があれば、その約30分前に通知を予約する。
    /// 既存の予約は毎回入れ替える(予報の更新に追従)。
    ///
    /// 判定は降水確率のみで行う(天気種別と組み合わせない)。日本近域では天気種別が
    /// 気象庁モデル、降水確率が補完用のグローバルモデルという別ソースから来るため、
    /// 両方が同時に「雨」を示すことを要求すると、モデル間の見解の差で条件を満たせず
    /// 通知が飛ばないことがある(傘指数と同じ原因の不具合)。
    func scheduleRainAlert(for weather: WeatherBundle, placeName: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.rainAlertID])

        let now = Date()
        guard let rainHour = weather.hours.first(where: { hour in
            hour.date > now.addingTimeInterval(45 * 60) &&
            hour.date < now.addingTimeInterval(12 * 3600) &&
            (hour.precipitationProbability ?? 0) >= 50
        }) else { return }

        let fireDate = rainHour.date.addingTimeInterval(-30 * 60)
        guard fireDate > now else { return }

        let content = UNMutableNotificationContent()
        let isSnow = rainHour.kind == .snow
        let label = isSnow ? "雪" : "雨"
        content.title = isSnow ? "☃️ まもなく雪の予報" : "☔️ まもなく雨の予報"
        content.body = "\(placeName)では\(rainHour.date.hourLabel(in: weather.timeZone))ごろから\(label)の見込みです(降水確率\(Int(rainHour.precipitationProbability ?? 0))%)。"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: fireDate.timeIntervalSince(now),
            repeats: false
        )
        center.add(UNNotificationRequest(identifier: Self.rainAlertID, content: content, trigger: trigger))
    }

    func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.rainAlertID])
    }
}
