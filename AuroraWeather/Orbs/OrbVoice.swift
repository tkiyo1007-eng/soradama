import Foundation

/// 「そらだまの一言」— 天気・気温・時間帯から、その日だけの短いセリフを選ぶ。
/// アプリに小さな人格を持たせるための、かわいさ担当のロジック。
enum OrbVoice {
    /// このあと雨が来るとみなす降水確率のしきい値
    private static let rainComingThreshold: Double = 60

    static func line(for weather: WeatherBundle) -> String {
        var pool = lines(for: weather.kind, isDay: weather.isDay)
        // 今は降っていなくても、このあと雨が来るならそれを最優先で伝える。
        // 「空にひとつも雲がありません」の真下に傘指数82%が並ぶと、
        // どちらの数字も正しくてもアプリが壊れているように見えてしまう。
        if weather.kind.isDry,
           let probability = weather.maxPrecipitationProbability(withinHours: 12),
           probability >= rainComingThreshold {
            pool = rainComingLines
        } else if weather.temperature >= 33 {
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

    /// 過去の空玉に対する一言(コレクションの詳細表示用)。
    /// その日と同じ日付シードを使うので、記録当日に表示された一言と概ね一致する。
    static func line(for orb: DailyOrb) -> String {
        var pool = lines(for: orb.kind, isDay: true)
        if orb.tempMax >= 33 {
            pool = hotLines
        } else if orb.tempMax <= 2 {
            pool = coldLines
        }
        let key = orb.dateKey + orb.kind.label
        var generator = SeededRandom(seed: stableSeed(for: key))
        let index = Int(generator.next() * Double(pool.count)) % max(pool.count, 1)
        return pool[index]
    }

    private static let rainComingLines = [
        String(localized: "今は晴れ、でも傘はお守りに"),
        String(localized: "このあと空が崩れそうです"),
        String(localized: "雨の気配がひそんでいます"),
    ]

    private static let hotLines = [
        String(localized: "空玉、あつあつです"),
        String(localized: "今日の玉、湯気が出そう"),
        String(localized: "溶けそうなくらい晴れています"),
    ]

    private static let coldLines = [
        String(localized: "空玉、キンと冷えています"),
        String(localized: "今日の空、指先まで冷たそう"),
        String(localized: "凍える空をお届けします"),
    ]

    private static func lines(for kind: WeatherKind, isDay: Bool) -> [String] {
        switch kind {
        case .clear:
            return isDay
                ? [String(localized: "澄みきった一日になりそう"),
                   String(localized: "今日の玉、とびきり透明です"),
                   String(localized: "空にひとつも雲がありません")]
                : [String(localized: "静かな夜の玉ができました"),
                   String(localized: "今日は星がよく見えそう"),
                   String(localized: "夜空がひときわ澄んでいます")]
        case .partlyCloudy:
            return [String(localized: "雲がゆっくり流れています"),
                    String(localized: "晴れと雲、半分こな一日"),
                    String(localized: "今日の玉、少しふわふわです")]
        case .cloudy:
            return [String(localized: "やわらかい光の一日です"),
                    String(localized: "今日の空、綿菓子みたい"),
                    String(localized: "雲に包まれた玉になりました")]
        case .fog:
            return [String(localized: "白い霧に包まれています"),
                    String(localized: "今日の玉、ぼんやり霞んでいます"),
                    String(localized: "視界の先が優しく滲む一日")]
        case .drizzle:
            return [String(localized: "こまかい雨が降っています"),
                    String(localized: "今日の玉、しっとり濡れています"),
                    String(localized: "傘は軽めで大丈夫そう")]
        case .rain:
            return [String(localized: "雨粒が玉に閉じ込められました"),
                    String(localized: "今日はしっとりした一日です"),
                    String(localized: "雨音を楽しむ日にしましょう")]
        case .snow:
            return [String(localized: "粉雪が舞い込んだ玉です"),
                    String(localized: "今日の空、真っ白です"),
                    String(localized: "足元に気をつけてお出かけを")]
        case .thunderstorm:
            return [String(localized: "空が少し騒がしいようです"),
                    String(localized: "今日の玉、ぴりっとしています"),
                    String(localized: "雷の音にご注意ください")]
        }
    }
}
