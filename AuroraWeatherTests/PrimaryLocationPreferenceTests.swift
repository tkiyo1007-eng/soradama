import Foundation
import Testing
@testable import AuroraWeather

/// 世界のどこで使っても、利用者が選んだ「自分の空」を東京や測位結果で
/// 勝手に置き換えないための永続化・移行ポリシー。
struct PrimaryLocationPreferenceTests {
    @Test("選択都市モードでは起動時に現在地で上書きしない")
    func selectedCityDoesNotResolveCurrentLocation() {
        let paris = SavedPlace(
            name: "Paris",
            detail: "France",
            latitude: 48.8566,
            longitude: 2.3522
        )
        let preference = PrimaryLocationPreference(mode: .selectedCity, place: paris)

        #expect(!SharedStore.shouldResolveCurrentLocation(for: preference))
    }

    @Test("現在地モードと旧版利用者は起動時に測位を試す")
    func currentAndLegacyModesResolveCurrentLocation() {
        let previousLocation = SavedPlace(
            name: "Current Location",
            detail: "United States",
            latitude: 37.7749,
            longitude: -122.4194,
            isCurrentLocation: true
        )
        let current = PrimaryLocationPreference(
            mode: .currentLocation,
            place: previousLocation
        )

        #expect(SharedStore.shouldResolveCurrentLocation(for: current))
        #expect(SharedStore.shouldResolveCurrentLocation(for: nil))
    }

    @Test("ホーム地点は選択方法とWidget互換地点へ同時に保存される")
    func primaryLocationPersistsModeAndLegacyPlace() throws {
        let first = Self.makeDefaults()
        let shared = Self.makeDefaults()
        defer {
            Self.clear(first)
            Self.clear(shared)
        }
        let sydney = SavedPlace(
            name: "Sydney",
            detail: "Australia",
            latitude: -33.8688,
            longitude: 151.2093
        )
        let preference = PrimaryLocationPreference(mode: .selectedCity, place: sydney)

        SharedStore.savePrimaryLocation(preference, to: [first.defaults, shared.defaults])

        #expect(
            SharedStore.primaryLocationPreference(from: [first.defaults, shared.defaults])
                == preference
        )
        #expect(SharedStore.lastPlace(from: [first.defaults, shared.defaults]) == sydney)
        #expect(first.defaults.data(forKey: SharedStore.lastPlaceKey) != nil)
        #expect(shared.defaults.data(forKey: SharedStore.primaryLocationPreferenceKey) != nil)
    }

    @Test("東京を明示選択した場合も未設定扱いに戻らない")
    func explicitlySelectedTokyoPersists() {
        let store = Self.makeDefaults()
        defer { Self.clear(store) }
        let tokyo = SavedPlace(
            name: "Tokyo",
            detail: "Japan",
            latitude: 35.6895,
            longitude: 139.6917
        )

        SharedStore.savePrimaryLocation(
            PrimaryLocationPreference(mode: .selectedCity, place: tokyo),
            to: [store.defaults]
        )

        let restored = SharedStore.primaryLocationPreference(from: [store.defaults])
        #expect(restored?.mode == .selectedCity)
        #expect(restored?.place == tokyo)
        #expect(!SharedStore.shouldResolveCurrentLocation(for: restored))
    }

    @Test("共有ストア側の新しい設定を優先する")
    func sharedStoreTakesPrecedence() {
        let standard = Self.makeDefaults()
        let shared = Self.makeDefaults()
        defer {
            Self.clear(standard)
            Self.clear(shared)
        }
        let london = SavedPlace(name: "London", detail: "United Kingdom", latitude: 51.5072, longitude: -0.1276)
        let berlin = SavedPlace(name: "Berlin", detail: "Germany", latitude: 52.52, longitude: 13.405)
        SharedStore.savePrimaryLocation(
            PrimaryLocationPreference(mode: .selectedCity, place: london),
            to: [standard.defaults]
        )
        SharedStore.savePrimaryLocation(
            PrimaryLocationPreference(mode: .selectedCity, place: berlin),
            to: [shared.defaults]
        )

        let restored = SharedStore.primaryLocationPreference(
            from: [standard.defaults, shared.defaults]
        )
        #expect(restored?.place == berlin)
    }

    private struct TestDefaults {
        let suiteName: String
        let defaults: UserDefaults
    }

    private static func makeDefaults() -> TestDefaults {
        let suiteName = "PrimaryLocationPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return TestDefaults(suiteName: suiteName, defaults: defaults)
    }

    private static func clear(_ store: TestDefaults) {
        store.defaults.removePersistentDomain(forName: store.suiteName)
    }
}
