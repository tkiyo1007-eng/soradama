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

    private var language: String { Self.languageCode(for: .current) }

    func search(_ query: String) async throws -> [GeoPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else { return [] }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            .init(name: "name", value: trimmed),
            .init(name: "count", value: "12"),
            .init(name: "language", value: language),
            .init(name: "format", value: "json"),
        ]
        guard let url = components?.url else { return [] }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
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
