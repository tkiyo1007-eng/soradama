import Foundation

/// Widget と Watch が圏外でも直近の天気を表示するための共有キャッシュ。
///
/// 地点 ID と座標をレコードに含め、移動後に別の都市の天気を誤表示しないようにする。
/// 現在の天気として信頼できる期間を優先して最大 6 時間とし、期限切れや壊れた
/// データは必ず無視する。
enum WeatherSnapshotCache {
    static let storageKey = "aurora.weatherSnapshot.v2"
    static let maximumAge: TimeInterval = 6 * 60 * 60
    /// GPS の揺れは許容しつつ、別の街へ移動したキャッシュは使わない距離。
    static let currentLocationTolerance: Double = 10_000

    struct Snapshot: Codable {
        let schemaVersion: Int
        let placeID: String
        let latitude: Double
        let longitude: Double
        let weather: WeatherBundle
        let savedAt: Date

        init(place: SavedPlace, weather: WeatherBundle, savedAt: Date) {
            schemaVersion = 2
            placeID = place.id
            latitude = place.latitude
            longitude = place.longitude
            self.weather = weather
            self.savedAt = savedAt
        }
    }

    /// アプリ、Widget 拡張、Watch アプリのそれぞれのローカル領域と
    /// App Group の両方に保存する。
    static func save(
        _ weather: WeatherBundle,
        for place: SavedPlace,
        now: Date = .now
    ) {
        save(weather, place: place, now: now, to: defaultStores)
    }

    static func load(
        for place: SavedPlace,
        now: Date = .now
    ) -> WeatherBundle? {
        loadSnapshot(for: place, now: now)?.weather
    }

    static func loadSnapshot(
        for place: SavedPlace,
        now: Date = .now
    ) -> Snapshot? {
        load(place: place, now: now, from: defaultStores)
    }

    // MARK: - テスト可能な保存本体

    static func save(
        _ weather: WeatherBundle,
        place: SavedPlace,
        now: Date,
        to stores: [UserDefaults]
    ) {
        let snapshot = Snapshot(place: place, weather: weather, savedAt: now)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        for store in stores {
            store.set(data, forKey: storageKey)
        }
    }

    /// 複数ストアに差がある場合は、条件を満たす最新レコードを返す。
    static func load(
        place: SavedPlace,
        now: Date,
        maximumAge: TimeInterval = WeatherSnapshotCache.maximumAge,
        from stores: [UserDefaults]
    ) -> Snapshot? {
        stores.compactMap { store -> Snapshot? in
            guard let data = store.data(forKey: storageKey),
                  let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
                  isValid(
                      snapshot,
                      for: place,
                      now: now,
                      maximumAge: maximumAge
                  ) else {
                return nil
            }
            return snapshot
        }
        .max { $0.savedAt < $1.savedAt }
    }

    static func isValid(
        _ snapshot: Snapshot,
        for place: SavedPlace,
        now: Date,
        maximumAge: TimeInterval = WeatherSnapshotCache.maximumAge
    ) -> Bool {
        guard snapshot.schemaVersion == 2,
              !place.id.isEmpty,
              snapshot.placeID == place.id,
              snapshot.latitude.isFinite,
              (-90...90).contains(snapshot.latitude),
              snapshot.longitude.isFinite,
              (-180...180).contains(snapshot.longitude),
              maximumAge >= 0 else {
            return false
        }

        let age = now.timeIntervalSince(snapshot.savedAt)
        guard age >= 0 && age <= maximumAge else { return false }

        // 現在地の ID は測位ごとの揺れを避けるため固定だが、座標まで固定すると
        // 旅行後に以前の街のキャッシュを表示してしまう。距離でも必ず照合する。
        guard place.isCurrentLocation else { return true }
        return distance(
            fromLatitude: snapshot.latitude,
            longitude: snapshot.longitude,
            toLatitude: place.latitude,
            longitude: place.longitude
        ) <= currentLocationTolerance
    }

    static func locationsAreNearby(_ first: SavedPlace, _ second: SavedPlace) -> Bool {
        distance(
            fromLatitude: first.latitude,
            longitude: first.longitude,
            toLatitude: second.latitude,
            longitude: second.longitude
        ) <= currentLocationTolerance
    }

    private static func distance(
        fromLatitude firstLatitude: Double,
        longitude firstLongitude: Double,
        toLatitude secondLatitude: Double,
        longitude secondLongitude: Double
    ) -> Double {
        let earthRadius = 6_371_000.0
        let firstLat = firstLatitude * .pi / 180
        let secondLat = secondLatitude * .pi / 180
        let deltaLat = (secondLatitude - firstLatitude) * .pi / 180
        let deltaLon = (secondLongitude - firstLongitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(firstLat) * cos(secondLat)
            * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    private static var defaultStores: [UserDefaults] {
        var stores: [UserDefaults] = [.standard]
        if let shared = UserDefaults(suiteName: SharedStore.appGroupID) {
            stores.append(shared)
        }
        return stores
    }
}
