import Foundation
import WatchConnectivity

/// iPhone 側のホーム地点・単位を、サーバーを介さずペアリング済みWatchへ同期する。
final class PhoneWatchSyncService: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchSyncService()

    /// activation callback と設定変更が別スレッドから同時に来ても、古いcontextが
    /// 新しいcontextを後から上書きしないよう全操作を同じキューへ直列化する。
    private let queue = DispatchQueue(label: "com.tkiyo1007.soradama.watch-sync.phone")
    private var pendingPayload: WatchSyncPayload?

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

    func sync(place: SavedPlace, units: UnitSystem) {
        let payload = WatchSyncPayload(place: place, units: units)
        queue.async { [weak self] in
            self?.pendingPayload = payload
            self?.sendLatestIfPossible()
        }
    }

    /// 必ず `queue` 上から呼ぶ。
    private func sendLatestIfPossible() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        guard let pendingPayload,
              let context = try? pendingPayload.encodedContext() else { return }
        try? session.updateApplicationContext(context)
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated, error == nil else { return }
        queue.async { [weak self] in self?.sendLatestIfPossible() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        queue.async { session.activate() }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        // 後からWatchアプリをインストール・再接続した場合も、次回の設定変更を
        // 待たずに保留中の最新値を再送する。
        queue.async { [weak self] in self?.sendLatestIfPossible() }
    }
}
