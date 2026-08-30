import Foundation
import Observation
import CoreLocation
import WidgetKit

@Observable
@MainActor
final class WeatherViewModel {
    /// 表示するページ(先頭: 現在地または前回の地点、以降: マイシティ)
    private(set) var pages: [SavedPlace] = []
    /// 現在表示中のページ(SavedPlace.id)
    var selectionID: String = SavedPlace.fallback.id

    private(set) var bundles: [String: WeatherBundle] = [:]
    private(set) var loadingIDs: Set<String> = []
    /// 直近の取得に失敗した地点 → エラーメッセージ(キャッシュがあれば表示は継続する)
    private(set) var errors: [String: String] = [:]

    private(set) var savedPlaces: [SavedPlace] = []
    private(set) var units: UnitSystem
    private(set) var rainAlertsEnabled: Bool
    private(set) var morningAlertsEnabled: Bool
    private(set) var streakRemindersEnabled: Bool
    /// 今日の空玉がはじめて記録された瞬間のイベント(お祝いトースト用)
    private(set) var lastOrbEvent: OrbRecordResult?
    /// ホーム地点が現在地か、利用者が明示的に選んだ都市か。
    /// `nil` はこの設定がまだ無かった旧バージョンからの移行状態。
    private(set) var primaryLocationMode: PrimaryLocationMode?
    /// オンボーディングや地点選択シートに表示する、直近の測位エラー。
    private(set) var locationSelectionError: String?

    private var primaryPlace: SavedPlace
    private let weatherService = WeatherService()
    private let locationService = LocationService()
    private let cache = WeatherCache()
    private let notifications = NotificationService()

    private static let placesKey = "aurora.savedPlaces"
    private static let rainAlertsKey = "aurora.rainAlerts"
    private static let morningAlertsKey = "aurora.morningAlerts"
    private static let streakRemindersKey = "aurora.streakReminders"

    init() {
        let locationPreference = SharedStore.primaryLocationPreference()
        primaryPlace = locationPreference?.place ?? SharedStore.lastPlace()
        primaryLocationMode = locationPreference?.mode
        rainAlertsEnabled = UserDefaults.standard.bool(forKey: Self.rainAlertsKey)
        morningAlertsEnabled = UserDefaults.standard.bool(forKey: Self.morningAlertsKey)
        streakRemindersEnabled = UserDefaults.standard.bool(forKey: Self.streakRemindersKey)
        units = SharedStore.units()
        if let data = UserDefaults.standard.data(forKey: Self.placesKey),
           let stored = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            savedPlaces = stored
        }
        selectionID = primaryPlace.id
        rebuildPages()
        // キャッシュ読み込みはディスクI/Oなので起動をブロックしないよう非同期に
        Task { @MainActor in
            let cached = await cache.load()
            for (key, value) in cached where bundles[key] == nil {
                bundles[key] = value
            }
        }
    }

    // MARK: - 現在ページの便宜プロパティ

    var currentBundle: WeatherBundle? { bundles[selectionID] }
    var currentKind: WeatherKind { currentBundle?.kind ?? .partlyCloudy }
    var currentIsDay: Bool { currentBundle?.isDay ?? true }

    // MARK: - 読み込み

    func loadInitial() async {
        let preference = primaryLocationMode.map {
            PrimaryLocationPreference(mode: $0, place: primaryPlace)
        }
        // 明示的に都市をホームへ選んだ場合は、以後の起動で測位結果に上書きしない。
        // 設定が無い旧版利用者だけは互換性のため従来どおり現在地を一度試す。
        if SharedStore.shouldResolveCurrentLocation(for: preference),
           let located = try? await resolveCurrentLocation() {
            setPrimaryPlace(located, mode: .currentLocation)
        }
        await ensureLoaded(selectionID, force: true)

        // 残りのページは裏で先読みしておく
        for page in pages where page.id != selectionID {
            let id = page.id
            Task { await self.ensureLoaded(id) }
        }
    }

    /// 指定ページのデータを(未取得または30分以上古い場合に)取得する
    func ensureLoaded(_ id: String, force: Bool = false) async {
        guard let place = pages.first(where: { $0.id == id }) else { return }
        if !force,
           let bundle = bundles[id],
           Date().timeIntervalSince(bundle.fetchedAt) < 1800,
           errors[id] == nil {
            return
        }
        guard !loadingIDs.contains(id) else { return }
        loadingIDs.insert(id)
        defer { loadingIDs.remove(id) }

        do {
            let bundle = try await weatherService.fetch(latitude: place.latitude, longitude: place.longitude)
            bundles[id] = bundle
            errors[id] = nil
            // 表示中の地点ぶんだけ残す(削除した地点のデータが残り続けないように)
            let keep = Set(pages.map(\.id))
            let snapshot = bundles
            Task.detached { await self.cache.save(snapshot, keeping: keep) }
            if id == primaryPlace.id {
                // Widget/Watch が次の通信失敗時にも同じホーム地点を表示できるよう、
                // 本体で取得できた時点で共有スナップショットも更新する。
                WeatherSnapshotCache.save(bundle, for: place)
                if let primaryLocationMode {
                    SharedStore.savePrimaryLocation(place, mode: primaryLocationMode)
                } else {
                    // 設定キーを持たない旧版利用者の互換経路。
                    SharedStore.saveLastPlace(place)
                }
                PhoneWatchSyncService.shared.sync(place: place, units: units)
                WidgetCenter.shared.reloadAllTimelines()
                if rainAlertsEnabled {
                    notifications.scheduleRainAlert(for: bundle, placeName: place.name)
                }
                if morningAlertsEnabled {
                    notifications.scheduleMorningUmbrella(for: bundle, placeName: place.name)
                }
                // 今日の空玉を記録(利用者が選んだホーム地点だけがコレクションになる)。
                // 今日はじめての記録ならお祝いトーストを出し、ウィジェットにも反映する
                let result = OrbStore.shared.recordToday(
                    from: bundle,
                    placeName: place.name,
                    latitude: place.latitude
                )
                if result.isFirstToday {
                    lastOrbEvent = result
                }
                if streakRemindersEnabled {
                    notifications.scheduleStreakReminder(streak: result.streak)
                }
            }
        } catch {
            // 現在条件として古すぎる値は残さない。ホーム地点なら座標照合済みの
            // 共有キャッシュを使い、旅行後に以前の街の天気を出さない。
            if let existing = bundles[id],
               Date().timeIntervalSince(existing.fetchedAt) > WeatherSnapshotCache.maximumAge {
                bundles[id] = nil
            }
            if bundles[id] == nil,
               id == primaryPlace.id,
               let cached = WeatherSnapshotCache.loadSnapshot(for: place) {
                bundles[id] = cached.weather
            }
            errors[id] = error.soradamaMessage
        }
    }

    /// 検索結果から地点を選択(未保存ならマイシティへ追加してからページ移動)。
    /// 通常の都市閲覧ではホーム地点を変えず、通知・Widget・空玉への意図しない影響を防ぐ。
    func selectSearched(_ place: SavedPlace) async {
        if place.id != primaryPlace.id, !savedPlaces.contains(where: { $0.id == place.id }) {
            savedPlaces.append(place)
            persistPlaces()
            rebuildPages()
        }
        selectionID = place.id
        Haptics.selection()
        await ensureLoaded(place.id)
    }

    /// オンボーディングで選んだ都市をホーム地点として保存する。
    /// 空玉・通知・Widget はすべてこの地点を使う。
    func selectPrimaryCity(_ place: SavedPlace) async {
        if !savedPlaces.contains(where: { $0.id == place.id }) {
            savedPlaces.append(place)
            persistPlaces()
        }
        setPrimaryPlace(place, mode: .selectedCity)
        locationSelectionError = nil
        Haptics.selection()
        // 地点の確定と永続化は通信を待たずに完了させる。
        // 圏外でもオンボーディングを抜けられ、天気はメイン画面で再試行できる。
        Task { await self.ensureLoaded(place.id) }
    }

    /// 現在地をホームへ戻す。成功したときだけ選択モードも更新する。
    @discardableResult
    func useCurrentLocation() async -> Bool {
        do {
            let located = try await resolveCurrentLocation()
            setPrimaryPlace(located, mode: .currentLocation)
            locationSelectionError = nil
            Task { await self.ensureLoaded(located.id, force: true) }
            return true
        } catch {
            locationSelectionError = error.soradamaMessage
            return false
        }
    }

    private func resolveCurrentLocation() async throws -> SavedPlace {
        let location = try await locationService.currentLocation()
        var name = String(localized: "現在地")
        var detail = ""
        if let placemark = try? await CLGeocoderBox.reverseGeocode(location) {
            name = placemark.locality
                ?? placemark.administrativeArea
                ?? String(localized: "現在地")
            detail = placemark.country ?? ""
        }
        return SavedPlace(
            name: name,
            detail: detail,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            isCurrentLocation: true
        )
    }

    /// ホーム地点・選択モード・Widget互換用地点を、読み込みより先に確定する。
    /// 通信に失敗しても次回起動で利用者の選択が失われない。
    private func setPrimaryPlace(_ place: SavedPlace, mode: PrimaryLocationMode) {
        if primaryPlace.isCurrentLocation,
           place.isCurrentLocation,
           !WeatherSnapshotCache.locationsAreNearby(primaryPlace, place) {
            // 現在地の ID は固定なので、遠くへ移動したときは同じ辞書キーに残る
            // 以前の街の天気を先に破棄する。
            bundles[place.id] = nil
            errors[place.id] = nil
        }
        primaryPlace = place
        primaryLocationMode = mode
        SharedStore.savePrimaryLocation(place, mode: mode)
        PhoneWatchSyncService.shared.sync(place: place, units: units)
        rebuildPages()
        selectionID = place.id
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - 保存地点

    func save(place newPlace: SavedPlace) {
        guard !savedPlaces.contains(where: { $0.id == newPlace.id }) else { return }
        savedPlaces.append(newPlace)
        persistPlaces()
        rebuildPages()
    }

    func removePlaces(at offsets: IndexSet) {
        let removedIDs = offsets.map { savedPlaces[$0].id }
        savedPlaces.remove(atOffsets: offsets)
        persistPlaces()
        rebuildPages()
        // 表示中のページが消えた場合は先頭へ戻す
        if removedIDs.contains(selectionID) {
            selectionID = primaryPlace.id
        }
    }

    private func rebuildPages() {
        var result = [primaryPlace]
        for place in savedPlaces where place.id != primaryPlace.id {
            result.append(place)
        }
        pages = result
    }

    private func persistPlaces() {
        if let data = try? JSONEncoder().encode(savedPlaces) {
            UserDefaults.standard.set(data, forKey: Self.placesKey)
        }
    }

    // MARK: - 雨の通知

    func setRainAlerts(_ enabled: Bool) async {
        if enabled {
            let granted = await notifications.requestAuthorization()
            rainAlertsEnabled = granted
            if granted, let bundle = bundles[primaryPlace.id] {
                notifications.scheduleRainAlert(for: bundle, placeName: primaryPlace.name)
            }
        } else {
            rainAlertsEnabled = false
            notifications.cancel()
        }
        UserDefaults.standard.set(rainAlertsEnabled, forKey: Self.rainAlertsKey)
    }

    func setMorningAlerts(_ enabled: Bool) async {
        if enabled {
            let granted = await notifications.requestAuthorization()
            morningAlertsEnabled = granted
            if granted, let bundle = bundles[primaryPlace.id] {
                notifications.scheduleMorningUmbrella(for: bundle, placeName: primaryPlace.name)
            }
        } else {
            morningAlertsEnabled = false
            notifications.cancelMorningUmbrella()
        }
        UserDefaults.standard.set(morningAlertsEnabled, forKey: Self.morningAlertsKey)
    }

    func setStreakReminders(_ enabled: Bool) async {
        if enabled {
            let granted = await notifications.requestAuthorization()
            streakRemindersEnabled = granted
            if granted {
                notifications.scheduleStreakReminder(streak: OrbStore.shared.streak)
            }
        } else {
            streakRemindersEnabled = false
            notifications.cancelStreakReminder()
        }
        UserDefaults.standard.set(streakRemindersEnabled, forKey: Self.streakRemindersKey)
    }

    // MARK: - 表示設定

    /// 気温の単位を変更して保存する(次回起動時も維持される)。
    /// ウィジェットや Watch にも同じ単位を反映させるため App Group にも書き込み、
    /// ウィジェットのタイムラインを再読み込みさせる。
    func setUnits(_ newUnits: UnitSystem) {
        guard newUnits != units else { return }
        units = newUnits
        SharedStore.saveUnits(newUnits)
        PhoneWatchSyncService.shared.sync(place: primaryPlace, units: newUnits)
        WidgetCenter.shared.reloadAllTimelines()
        Haptics.selection()
    }

    // MARK: - 表示用フォーマット

    func degrees(_ celsius: Double) -> String {
        "\(Int(units.convert(celsius).rounded()))°"
    }
}

// MARK: - 逆ジオコーディング(名前解決)

enum CLGeocoderBox {
    static func reverseGeocode(_ location: CLLocation) async throws -> CLPlacemark? {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale.current)
        return placemarks.first
    }
}
