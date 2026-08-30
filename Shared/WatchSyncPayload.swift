import Foundation

/// iPhone で選んだ「自分の空」と表示単位を Apple Watch へ渡す内容。
///
/// App Group は同じ端末内のアプリと拡張間の共有であり、iPhone と Watch の
/// 端末間同期には使えないため、WatchConnectivity の application context に載せる。
struct WatchSyncPayload: Codable, Equatable {
    static let contextKey = "soradama.watchSettings.v1"

    let place: SavedPlace
    let units: UnitSystem
    let sentAt: Date

    init(place: SavedPlace, units: UnitSystem, sentAt: Date = .now) {
        self.place = place
        self.units = units
        self.sentAt = sentAt
    }

    func encodedContext() throws -> [String: Any] {
        [Self.contextKey: try JSONEncoder().encode(self)]
    }

    static func decode(from context: [String: Any]) throws -> WatchSyncPayload? {
        guard let data = context[contextKey] as? Data else { return nil }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    /// activation時のcontextとリアルタイム通知が前後しても、新しい設定を
    /// 古いpayloadで上書きしないための共通判定。
    func isNewer(than lastAppliedAt: Date?) -> Bool {
        guard let lastAppliedAt else { return true }
        return sentAt > lastAppliedAt
    }
}
