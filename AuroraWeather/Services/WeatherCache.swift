import Foundation

/// 地点ごとの最終取得データをディスクに保存するオフラインキャッシュ。
/// 圏外や API 障害時にも、最後に取得できた天気を表示できるようにする。
///
/// 書き込みはメインスレッドを塞がないよう actor 上で直列に行う。
/// また、削除した地点のデータが残り続けないよう、保存時に不要な項目を間引く。
actor WeatherCache {
    private let fileURL: URL
    /// これより古いキャッシュは表示に使えないので捨てる
    private static let maxAge: TimeInterval = 3 * 24 * 3600

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("weather-cache.json")
        // 天気は再取得できるので、iCloud/iTunes のバックアップ対象から外す
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    func load() -> [String: WeatherBundle] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: WeatherBundle].self, from: data) else {
            return [:]
        }
        // 古すぎるものは読み込み時点で捨てる
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        return decoded.filter { $0.value.fetchedAt > cutoff }
    }

    /// `keeping` に含まれる地点だけを、期限内のものに絞って保存する。
    func save(_ bundles: [String: WeatherBundle], keeping ids: Set<String>) {
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        let trimmed = bundles.filter { ids.contains($0.key) && $0.value.fetchedAt > cutoff }
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
