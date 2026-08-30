import Foundation
import Testing
@testable import AuroraWeather

struct WatchSyncPayloadTests {
    @Test("Watch同期の地点と単位をapplication contextで往復できる")
    func contextRoundTrip() throws {
        let place = SavedPlace(
            name: "Sydney",
            detail: "Australia",
            latitude: -33.8688,
            longitude: 151.2093
        )
        let payload = WatchSyncPayload(
            place: place,
            units: .fahrenheit,
            sentAt: Date(timeIntervalSince1970: 1_788_000_000)
        )

        let context = try payload.encodedContext()
        let maybeDecoded = try WatchSyncPayload.decode(from: context)
        let decoded = try #require(maybeDecoded)
        #expect(decoded == payload)
    }

    @Test("別用途のapplication contextは無視する")
    func unrelatedContextIsIgnored() throws {
        #expect(try WatchSyncPayload.decode(from: ["other": Data()]) == nil)
    }

    @Test("Watchは最後に反映した時刻より新しい設定だけを受け入れる")
    func rejectsOutOfOrderPayloads() {
        let place = SavedPlace.fallback
        let older = WatchSyncPayload(
            place: place,
            units: .celsius,
            sentAt: Date(timeIntervalSince1970: 100)
        )
        let newer = WatchSyncPayload(
            place: place,
            units: .fahrenheit,
            sentAt: Date(timeIntervalSince1970: 200)
        )

        #expect(older.isNewer(than: nil))
        #expect(newer.isNewer(than: older.sentAt))
        #expect(!older.isNewer(than: newer.sentAt))
        #expect(!newer.isNewer(than: newer.sentAt))
    }
}
