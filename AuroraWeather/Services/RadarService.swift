import Foundation

/// 気象庁「高解像度降水ナウキャスト」のタイル情報。
///
/// 以前は RainViewer を使っていたが、あちらは個人利用・教育利用に限られる
/// ライセンスだったため、商用利用が明示的に認められている気象庁のデータへ移した。
/// 副次的に、日本国内の解像度が大きく上がっている
/// (RainViewer はズームレベル7が上限だったのに対し、気象庁は10まで提供される)。
///
/// - 実況(N1): 5分刻みで過去3時間ぶん
/// - 予測(N2): 5分刻みで60分先まで
struct RadarFrame: Identifiable, Equatable {
    /// 解析の基準時刻 (yyyyMMddHHmmss・JST)
    let baseTime: String
    /// このコマが表している時刻 (yyyyMMddHHmmss・JST)
    let validTime: String
    let isForecast: Bool

    var id: String { "\(baseTime)-\(validTime)" }
    var date: Date { RadarService.parse(validTime) ?? .distantPast }
}

struct RadarService {
    private struct TargetTime: Decodable {
        let basetime: String
        let validtime: String
    }

    /// 気象庁ナウキャストが覆っているのは日本周辺だけ。
    /// 海外の地点でシートを開いても真っ暗な地図が出るだけなので、
    /// 呼び出し側でこれを見て「提供範囲外」と案内する。
    static func isCovered(latitude: Double, longitude: Double) -> Bool {
        (20.0...50.0).contains(latitude) && (118.0...150.0).contains(longitude)
    }

    /// 実況と予測をまとめて取得し、古い順に並べて返す。
    ///
    /// どちらの JSON も「新しい順」で返ってくる点に注意。
    /// また5分刻みのままだと実況だけで36コマになりアニメーションが冗長なので、
    /// 10分刻みへ間引いている。
    func fetchFrames() async throws -> [RadarFrame] {
        async let pastTask = load(kind: "N1")
        async let forecastTask = load(kind: "N2")
        let (past, forecast) = try await (pastTask, forecastTask)

        // 実況: 直近1時間ぶんを10分刻みで
        let recentPast = Array(past.prefix(12))
            .enumerated()
            .filter { $0.offset % 2 == 0 }
            .map { RadarFrame(baseTime: $0.element.basetime, validTime: $0.element.validtime, isForecast: false) }
            .reversed()

        // 予測: 60分先までを10分刻みで
        let nowcast = Array(forecast)
            .enumerated()
            .filter { $0.offset % 2 == 0 }
            .map { RadarFrame(baseTime: $0.element.basetime, validTime: $0.element.validtime, isForecast: true) }
            .reversed()

        return Array(recentPast) + Array(nowcast)
    }

    private func load(kind: String) async throws -> [TargetTime] {
        guard let url = URL(string: "https://www.jma.go.jp/bosai/jmatile/data/nowc/targetTimes_\(kind).json") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([TargetTime].self, from: data)
    }

    // MARK: - 時刻の変換

    /// 気象庁の時刻文字列は JST の yyyyMMddHHmmss。
    private static let timeParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// DateFormatter は空文字や桁足らずを渡されると nil ではなく
    /// 2000年1月1日を返してくる。気象庁側の形式が変わったときに
    /// 「2000年のコマ」が静かに並ぶことになるので、先に桁と文字種を確かめる。
    static func parse(_ string: String) -> Date? {
        guard string.count == 14, string.allSatisfy(\.isNumber) else { return nil }
        return timeParser.date(from: string)
    }
}
