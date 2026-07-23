import Foundation

/// 「そらだまの一言」— 天気・気温・時間帯から、その日だけの短いセリフを選ぶ。
/// アプリに小さな人格を持たせるための、かわいさ担当のロジック。
enum OrbVoice {
    static func line(for weather: WeatherBundle) -> String {
        var pool = lines(for: weather.kind, isDay: weather.isDay)
        if weather.temperature >= 33 {
            pool = hotLines
        } else if weather.temperature <= 2 {
            pool = coldLines
        }
        // 日付でシードして、同じ日は同じセリフ・日が違えば変わる
        let key = DailyOrb.key(for: Date()) + weather.kind.label
        var generator = SeededRandom(seed: stableSeed(for: key))
        let index = Int(generator.next() * Double(pool.count)) % max(pool.count, 1)
        return pool[index]
    }

    private static let hotLines = [
        "空玉、あつあつです",
        "今日の玉、湯気が出そう",
        "溶けそうなくらい晴れています",
    ]

    private static let coldLines = [
        "空玉、キンと冷えています",
        "今日の空、指先まで冷たそう",
        "凍える空をお届けします",
    ]

    private static func lines(for kind: WeatherKind, isDay: Bool) -> [String] {
        switch kind {
        case .clear:
            return isDay
                ? ["澄みきった一日になりそう", "今日の玉、とびきり透明です", "空にひとつも雲がありません"]
                : ["静かな夜の玉ができました", "今日は星がよく見えそう", "夜空がひときわ澄んでいます"]
        case .partlyCloudy:
            return ["雲がゆっくり流れています", "晴れと雲、半分こな一日", "今日の玉、少しふわふわです"]
        case .cloudy:
            return ["やわらかい光の一日です", "今日の空、綿菓子みたい", "雲に包まれた玉になりました"]
        case .fog:
            return ["白い霧に包まれています", "今日の玉、ぼんやり霞んでいます", "視界の先が優しく滲む一日"]
        case .drizzle:
            return ["こまかい雨が降っています", "今日の玉、しっとり濡れています", "傘は軽めで大丈夫そう"]
        case .rain:
            return ["雨粒が玉に閉じ込められました", "今日はしっとりした一日です", "雨音を楽しむ日にしましょう"]
        case .snow:
            return ["粉雪が舞い込んだ玉です", "今日の空、真っ白です", "足元に気をつけてお出かけを"]
        case .thunderstorm:
            return ["空が少し騒がしいようです", "今日の玉、ぴりっとしています", "雷の音にご注意ください"]
        }
    }
}
