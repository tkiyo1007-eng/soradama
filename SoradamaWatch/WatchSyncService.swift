import Foundation
import WatchConnectivity
import WidgetKit

/// iPhone のホーム地点・単位を受け取り、Watchアプリとコンプリケーションで共有する。
final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()
    static let settingsDidChange = Notification.Name("soradama.watchSettingsDidChange")
    private static let hasReceivedSettingsKey = "soradama.watchSettings.hasReceived.v1"
    private static let lastAppliedAtKey = "soradama.watchSettings.lastAppliedAt.v1"
    private let queue = DispatchQueue(label: "com.tkiyo1007.soradama.watch-sync.watch")

    static var hasReceivedSettings: Bool {
        UserDefaults.standard.bool(forKey: hasReceivedSettingsKey)
    }

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated,
              error == nil,
              let payload = try? WatchSyncPayload.decode(from: session.receivedApplicationContext) else {
            return
        }
        enqueue(payload)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let payload = try? WatchSyncPayload.decode(from: applicationContext) else { return }
        enqueue(payload)
    }

    private func enqueue(_ payload: WatchSyncPayload) {
        // WatchWeatherModelもMainActor上でSharedStoreを読む・書くため、設定適用を
        // 同じexecutorへ寄せ、standard/App Groupの2書込み途中を観測させない。
        Task { @MainActor [weak self] in
            self?.applyIfNewest(payload)
        }
    }

    /// MainActor上で時刻判定から永続化までを一続きにし、古い設定の逆流を防ぐ。
    @MainActor
    private func applyIfNewest(_ payload: WatchSyncPayload) {
        let defaults = UserDefaults.standard
        let lastAppliedAt = defaults.object(forKey: Self.lastAppliedAtKey) as? Date
        guard payload.isNewer(than: lastAppliedAt) else { return }

        var localizedPlace = payload.place
        if payload.place.isCurrentLocation {
            localizedPlace = SavedPlace(
                name: String(localized: "現在地"),
                detail: payload.place.detail,
                latitude: payload.place.latitude,
                longitude: payload.place.longitude,
                isCurrentLocation: true
            )
        }
        SharedStore.saveLastPlace(localizedPlace)
        SharedStore.saveUnits(payload.units)
        defaults.set(payload.sentAt, forKey: Self.lastAppliedAtKey)
        defaults.set(true, forKey: Self.hasReceivedSettingsKey)
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: Self.settingsDidChange, object: nil)
    }

}
