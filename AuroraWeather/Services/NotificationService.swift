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

    // MARK: - 朝の傘予報

    static let morningAlertID = "soradama.morningUmbrella"

    /// 次の朝7時に、その日の傘の要否を届ける。
    /// 予約はアプリを開いた時点の予報に基づく(開くたびに入れ替わる)。
    func scheduleMorningUmbrella(for weather: WeatherBundle, placeName: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.morningAlertID])

        let calendar = Calendar.current
        guard let fireDate = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 7, minute: 0),
            matchingPolicy: .nextTime
        ) else { return }

        // 通知が鳴る朝7時から日中12時間ぶんの最大降水確率で判定する
        let windowEnd = fireDate.addingTimeInterval(12 * 3600)
        let probability = weather.hours
            .filter { $0.date >= fireDate && $0.date <= windowEnd }
            .compactMap(\.precipitationProbability)
            .max()
        guard let probability else { return }

        let content = UNMutableNotificationContent()
        switch probability {
        case 50...:
            content.title = "☔️ 今日は傘の出番です"
            content.body = "\(placeName)の日中の降水確率は最大\(Int(probability))%。傘を持ってお出かけください。"
        case 30..<50:
            content.title = "🌂 折りたたみ傘があると安心"
            content.body = "\(placeName)の日中の降水確率は最大\(Int(probability))%です。"
        default:
            content.title = "☀️ 今日は傘なしで大丈夫そう"
            content.body = "\(placeName)の日中の降水確率は最大\(Int(probability))%。よい一日を！"
        }
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.morningAlertID, content: content, trigger: trigger))
    }

    func cancelMorningUmbrella() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.morningAlertID])
    }

    // MARK: - 連続記録リマインド

    static let streakReminderID = "soradama.streakReminder"

    /// 連続記録が途切れそうな夜(翌日の20時)にそっと知らせる。
    /// 翌日アプリを開けば予約は入れ替わって鳴らない。開かなかった日だけ届く仕組み。
    func scheduleStreakReminder(streak: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.streakReminderID])
        // 続ける動機が生まれるのは数日続いてから
        guard streak >= 3 else { return }

        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
              let fireDate = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: tomorrow) else { return }

        let content = UNMutableNotificationContent()
        content.title = "🔮 連続\(streak)日の記録が今日で途切れそうです"
        content.body = "アプリを開くと今日の空玉を受け取れます。"
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.streakReminderID, content: content, trigger: trigger))
    }

    func cancelStreakReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.streakReminderID])
    }
}
