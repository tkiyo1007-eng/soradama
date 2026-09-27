import Foundation

/// GeoNamesの日本の自治体・区を使う、短い入力の補完。
/// 座標や名称を作らず、同梱の出典付きデータだけを検索する。
struct JapaneseCityIndex {
    struct Entry: Decodable {
        let id: Int
        let name: String
        let nameEn: String
        let aliases: [String]
        let prefecture: String
        let prefectureEn: String
        let latitude: Double
        let longitude: Double
        let population: Int
    }

    private struct Document: Decodable {
        let entries: [Entry]
    }

    private struct IndexedEntry {
        let entry: Entry
        let keys: [String]
    }

    static let bundled: JapaneseCityIndex = {
        // 同梱漏れ・破損時も既存のオンライン検索は使用できる。
        guard let url = Bundle.main.url(forResource: "JapaneseCityIndex", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let index = try? JapaneseCityIndex(data: data) else {
            return JapaneseCityIndex(entries: [])
        }
        return index
    }()

    private let indexed: [IndexedEntry]

    init(entries: [Entry]) {
        indexed = entries.map { entry in
            IndexedEntry(entry: entry, keys: Array(Set(([entry.name] + entry.aliases).map(Self.normalized))))
        }
    }

    init(data: Data) throws {
        self.init(entries: try JSONDecoder().decode(Document.self, from: data).entries)
    }

    func search(_ query: String, language: String, limit: Int = 12) -> [GeoPlace] {
        let key = Self.normalized(query)
        // ローマ字・郵便番号・海外の短い入力を日本の候補だけで置き換えない。
        guard let first = key.unicodeScalars.first, limit > 0,
              (0x3040...0x30FF).contains(first.value)
                || (0x3400...0x9FFF).contains(first.value)
                || (0xF900...0xFAFF).contains(first.value)
                || (0x20000...0x2FFFF).contains(first.value) else { return [] }
        return indexed.filter { $0.keys.contains { $0.hasPrefix(key) } }
            .sorted { lhs, rhs in
                let leftExact = lhs.keys.contains(key)
                let rightExact = rhs.keys.contains(key)
                if leftExact != rightExact { return leftExact }
                if lhs.entry.population != rhs.entry.population {
                    return lhs.entry.population > rhs.entry.population
                }
                return lhs.entry.id < rhs.entry.id
            }
            .prefix(limit)
            .map { item in
                let entry = item.entry
                return GeoPlace(id: entry.id,
                                name: language == "ja" ? entry.name : entry.nameEn,
                                latitude: entry.latitude, longitude: entry.longitude,
                                country: language == "ja" ? "日本" : "Japan",
                                admin1: language == "ja" ? entry.prefecture : entry.prefectureEn)
            }
    }

    private static func normalized(_ text: String) -> String {
        let folded = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "ja_JP"))
        return folded.applyingTransform(.hiraganaToKatakana, reverse: true) ?? folded
    }
}
