import Foundation

/// ホームとして使う地点の決め方。
///
/// 地点そのものとは別に保存しておくことで、都市を選んだ利用者の設定を
/// 次回起動時の測位結果で上書きしないようにする。
enum PrimaryLocationMode: String, Codable, Equatable {
    case currentLocation
    case selectedCity
}

/// ホーム地点と、その地点を選んだ方法を一組で永続化する値。
/// `lastPlaceKey` は旧バージョンと Widget の互換用に引き続き併記する。
struct PrimaryLocationPreference: Codable, Equatable {
    let mode: PrimaryLocationMode
    let place: SavedPlace
}

/// アプリとウィジェットで選択地点を共有するためのストア。
/// App Group が設定されていればそのコンテナを、なければ各ターゲットの
/// UserDefaults を使う(その場合ウィジェットは既定の東京にフォールバック)。
enum SharedStore {
    /// Signing & Capabilities で App Group を追加する場合はこの ID を使う
    static let appGroupID = "group.com.tkiyo1007.soradama"
    static let lastPlaceKey = "aurora.lastPlace"
    static let primaryLocationPreferenceKey = "aurora.primaryLocationPreference"
    static let unitsKey = "aurora.units"

    private static var stores: [UserDefaults] {
        var result: [UserDefaults] = [.standard]
        if let shared = UserDefaults(suiteName: appGroupID) {
            result.append(shared)
        }
        return result
    }

    static func saveLastPlace(_ place: SavedPlace) {
        saveLastPlace(place, to: stores)
    }

    /// 旧版・Widget が読む地点に加え、選択方法も同時に保存する。
    static func savePrimaryLocation(_ place: SavedPlace, mode: PrimaryLocationMode) {
        savePrimaryLocation(
            PrimaryLocationPreference(mode: mode, place: place),
            to: stores
        )
    }

    static func primaryLocationPreference() -> PrimaryLocationPreference? {
        primaryLocationPreference(from: stores)
    }

    /// `nil` は選択方法を保存していない旧版利用者。
    /// 旧版だけは従来どおり起動時に現在地を試し、明示的に都市を選んだ人だけは測位しない。
    static func shouldResolveCurrentLocation(for preference: PrimaryLocationPreference?) -> Bool {
        preference?.mode != .selectedCity
    }

    // MARK: - テスト可能な保存本体

    static func saveLastPlace(_ place: SavedPlace, to stores: [UserDefaults]) {
        guard let data = try? JSONEncoder().encode(place) else { return }
        for store in stores {
            store.set(data, forKey: lastPlaceKey)
        }
    }

    static func lastPlace() -> SavedPlace {
        lastPlace(from: stores)
    }

    static func lastPlace(from stores: [UserDefaults]) -> SavedPlace {
        for store in stores.reversed() {
            if let data = store.data(forKey: lastPlaceKey),
               let place = try? JSONDecoder().decode(SavedPlace.self, from: data) {
                return place
            }
        }
        return .fallback
    }

    static func savePrimaryLocation(
        _ preference: PrimaryLocationPreference,
        to stores: [UserDefaults]
    ) {
        guard let data = try? JSONEncoder().encode(preference) else { return }
        for store in stores {
            store.set(data, forKey: primaryLocationPreferenceKey)
        }
        saveLastPlace(preference.place, to: stores)
    }

    static func primaryLocationPreference(
        from stores: [UserDefaults]
    ) -> PrimaryLocationPreference? {
        for store in stores.reversed() {
            if let data = store.data(forKey: primaryLocationPreferenceKey),
               let preference = try? JSONDecoder().decode(
                   PrimaryLocationPreference.self,
                   from: data
               ) {
                return preference
            }
        }
        return nil
    }

    /// 気温の単位を保存する。ウィジェットや Watch でも同じ単位で表示するため、
    /// アプリ本体の UserDefaults だけでなく App Group にも書き込む。
    static func saveUnits(_ units: UnitSystem) {
        for store in stores {
            store.set(units.rawValue, forKey: unitsKey)
        }
    }

    static func units() -> UnitSystem {
        for store in stores.reversed() {
            if let raw = store.string(forKey: unitsKey), let units = UnitSystem(rawValue: raw) {
                return units
            }
        }
        return .localeDefault
    }
}
