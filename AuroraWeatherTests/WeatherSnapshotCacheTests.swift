import Foundation
import Testing
@testable import AuroraWeather

struct WeatherSnapshotCacheTests {
    @Test("天気キャッシュは全ストアに保存し最新の有効値を返す")
    func savesEveryStoreAndLoadsNewestValidSnapshot() throws {
        let first = try makeStore()
        let second = try makeStore()
        defer {
            clear(first)
            clear(second)
        }

        let now = Date(timeIntervalSince1970: 2_000_000)
        let tokyo = place(name: "Tokyo", latitude: 35.6895, longitude: 139.6917)
        WeatherSnapshotCache.save(
            bundle(temperature: 18),
            place: tokyo,
            now: now.addingTimeInterval(-60),
            to: [first.defaults, second.defaults]
        )

        #expect(first.defaults.data(forKey: WeatherSnapshotCache.storageKey) != nil)
        #expect(second.defaults.data(forKey: WeatherSnapshotCache.storageKey) != nil)

        WeatherSnapshotCache.save(
            bundle(temperature: 24),
            place: tokyo,
            now: now,
            to: [second.defaults]
        )

        let loaded = WeatherSnapshotCache.load(
            place: tokyo,
            now: now,
            from: [first.defaults, second.defaults]
        )
        #expect(loaded?.weather.temperature == 24)
        #expect(loaded?.savedAt == now)
    }

    @Test("同じ地点の6時間以内だけ復元する")
    func acceptsOnlyMatchingPlaceWithinSixHours() throws {
        let store = try makeStore()
        defer { clear(store) }

        let savedAt = Date(timeIntervalSince1970: 2_000_000)
        let tokyo = place(name: "Tokyo", latitude: 35.6895, longitude: 139.6917)
        let sydney = place(name: "Sydney", latitude: -33.8688, longitude: 151.2093)
        WeatherSnapshotCache.save(
            bundle(temperature: 20),
            place: tokyo,
            now: savedAt,
            to: [store.defaults]
        )

        #expect(
            WeatherSnapshotCache.load(
                place: tokyo,
                now: savedAt.addingTimeInterval(WeatherSnapshotCache.maximumAge),
                from: [store.defaults]
            ) != nil
        )
        #expect(
            WeatherSnapshotCache.load(
                place: tokyo,
                now: savedAt.addingTimeInterval(WeatherSnapshotCache.maximumAge + 1),
                from: [store.defaults]
            ) == nil
        )
        #expect(
            WeatherSnapshotCache.load(
                place: sydney,
                now: savedAt.addingTimeInterval(60),
                from: [store.defaults]
            ) == nil
        )
        #expect(
            WeatherSnapshotCache.load(
                place: tokyo,
                now: savedAt.addingTimeInterval(-1),
                from: [store.defaults]
            ) == nil
        )
    }

    @Test("破損したキャッシュを無視し、他の有効なストアへフォールバックする")
    func ignoresCorruptionAndFallsBackToAnotherStore() throws {
        let corrupt = try makeStore()
        let valid = try makeStore()
        defer {
            clear(corrupt)
            clear(valid)
        }

        corrupt.defaults.set(Data("not-json".utf8), forKey: WeatherSnapshotCache.storageKey)
        let now = Date(timeIntervalSince1970: 2_000_000)
        let london = place(name: "London", latitude: 51.5074, longitude: -0.1278)
        WeatherSnapshotCache.save(
            bundle(temperature: 16),
            place: london,
            now: now,
            to: [valid.defaults]
        )

        let loaded = WeatherSnapshotCache.load(
            place: london,
            now: now,
            from: [corrupt.defaults, valid.defaults]
        )
        #expect(loaded?.weather.temperature == 16)

        valid.defaults.set(Data([0xFF]), forKey: WeatherSnapshotCache.storageKey)
        #expect(
            WeatherSnapshotCache.load(
                place: london,
                now: now,
                from: [corrupt.defaults, valid.defaults]
            ) == nil
        )
    }

    @Test("現在地は固定IDでも移動後の別都市キャッシュを使わない")
    func currentLocationAlsoMatchesCoordinates() throws {
        let store = try makeStore()
        defer { clear(store) }

        let now = Date(timeIntervalSince1970: 2_000_000)
        let tokyo = place(
            name: "Current Location",
            latitude: 35.6895,
            longitude: 139.6917,
            isCurrentLocation: true
        )
        let nearbyTokyo = place(
            name: "Current Location",
            latitude: 35.7000,
            longitude: 139.7000,
            isCurrentLocation: true
        )
        let sydney = place(
            name: "Current Location",
            latitude: -33.8688,
            longitude: 151.2093,
            isCurrentLocation: true
        )
        #expect(tokyo.id == sydney.id)

        WeatherSnapshotCache.save(
            bundle(temperature: 21),
            place: tokyo,
            now: now,
            to: [store.defaults]
        )

        #expect(
            WeatherSnapshotCache.load(
                place: nearbyTokyo,
                now: now.addingTimeInterval(60),
                from: [store.defaults]
            ) != nil
        )
        #expect(
            WeatherSnapshotCache.load(
                place: sydney,
                now: now.addingTimeInterval(60),
                from: [store.defaults]
            ) == nil
        )
    }

    private struct TestStore {
        let name: String
        let defaults: UserDefaults
    }

    private func makeStore() throws -> TestStore {
        let name = "WeatherSnapshotCacheTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return TestStore(name: name, defaults: defaults)
    }

    private func clear(_ store: TestStore) {
        store.defaults.removePersistentDomain(forName: store.name)
    }

    private func place(
        name: String,
        latitude: Double,
        longitude: Double,
        isCurrentLocation: Bool = false
    ) -> SavedPlace {
        SavedPlace(
            name: name,
            detail: "",
            latitude: latitude,
            longitude: longitude,
            isCurrentLocation: isCurrentLocation
        )
    }

    private func bundle(temperature: Double) -> WeatherBundle {
        let date = Date(timeIntervalSince1970: 1_900_000)
        return WeatherBundle(
            fetchedAt: date,
            timeZoneID: "UTC",
            temperature: temperature,
            apparentTemperature: temperature,
            kind: .clear,
            isDay: true,
            humidity: 50,
            windSpeed: 3,
            windDirection: 180,
            pressure: 1013,
            uvIndex: 2,
            visibility: 10_000,
            sunrise: date,
            sunset: date.addingTimeInterval(43_200),
            hours: [],
            days: []
        )
    }
}
