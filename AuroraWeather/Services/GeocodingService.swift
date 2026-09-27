import Foundation

struct GeocodingService {
    /// 地名を返してもらう言語。
    ///
    /// ここを "ja" で固定していたため、英語で使っていても検索結果だけ
    /// 「ロンドン / イングランド / 英国」と日本語で出ていた。
    /// Open-Meteo の geocoding が対応するのは主要言語のみなので、
    /// 端末の言語が対応外なら英語に落とす。
    static func languageCode(for locale: Locale) -> String {
        let supported: Set<String> = ["en", "de", "fr", "es", "it", "pt", "ru", "tr", "hi", "ja", "zh"]
        let code = locale.language.languageCode?.identifier ?? "en"
        // 対応外の言語は英語に落とす。日本語に落とすと、読めない人のほうが多い。
        return supported.contains(code) ? code : "en"
    }

    private let language: String
    private let cityIndex: JapaneseCityIndex
    private let request: (URL) async throws -> (Data, URLResponse)

    init(locale: Locale = .current,
         cityIndex: JapaneseCityIndex = .bundled,
         request: @escaping (URL) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(from: $0) }) {
        self.language = Self.languageCode(for: locale)
        self.cityIndex = cityIndex
        self.request = request
    }

    func search(_ query: String) async throws -> [GeoPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else { return [] }
        try Task.checkCancellation()
        let local = cityIndex.search(trimmed, language: language)
        // Open-Meteoは1文字を検索せず、2文字は完全一致のみ。
        // 短い日本の地名は同梱候補を使い、接尾辞ごとの追加通信は行わない。
        if trimmed.count <= 2, !local.isEmpty { return local }
        guard trimmed.count >= 2 else { return [] }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            .init(name: "name", value: trimmed),
            .init(name: "count", value: "12"),
            .init(name: "language", value: language),
            .init(name: "format", value: "json"),
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        let (data, response) = try await request(url)
        try Task.checkCancellation()
        let remote = try Self.decode(data, response: response)
        // 通信失敗を空の成功に置き換えず、成功した結果にだけ補完する。
        // 海外・郵便番号検索の順序を保ち、同じ地点を重ねて表示しない。
        var ids = Set<Int>()
        var coordinates = Set<String>()
        return Array((remote + local).filter { place in
            guard !ids.contains(place.id), !coordinates.contains(place.asSavedPlace.id) else { return false }
            ids.insert(place.id)
            coordinates.insert(place.asSavedPlace.id)
            return true
        }.prefix(12))
    }

    static func decode(_ data: Data, response: URLResponse) throws -> [GeoPlace] {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        return decoded.results ?? []
    }
}

extension GeoPlace {
    var detailText: String {
        [admin1, country].compactMap { $0 }.joined(separator: " / ")
    }

    var asSavedPlace: SavedPlace {
        SavedPlace(name: name, detail: detailText, latitude: latitude, longitude: longitude)
    }
}
