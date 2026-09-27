import Testing
import Foundation
@testable import AuroraWeather

/// 英語対応が静かに崩れるのを防ぐためのテスト。
///
/// ローカライズは「翻訳が無い＝日本語がそのまま出る」という壊れ方をする。
/// ビルドは通り、日本語で使っているぶんには何も起きないので、
/// 英語版を実際に開くまで誰も気づけない。
struct LocalizationTests {

    /// 英語の訳が引けているかを、バンドルから直接確かめる。
    private func english(_ key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        let value = bundle.localizedString(forKey: key, value: "__missing__", table: nil)
        return value == "__missing__" ? nil : value
    }

    /// `String(localized:)` が現在選んでいるアプリ言語での期待値。
    /// 英語端末でも日本語端末でも、enumとString Catalogのキー対応を同じテストで検証する。
    private func currentLocalization(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    @Test("英語リソースがアプリに同梱されている")
    func englishBundleExists() throws {
        let path = Bundle.main.path(forResource: "en", ofType: "lproj")
        #expect(path != nil, "en.lproj が見つからない。英語版が丸ごと日本語で出てしまう")
    }

    /// 画面の要になる語。ここが欠けると英語版が一目で壊れて見える。
    @Test("主要な語に英訳がある",
          arguments: ["晴れ", "くもり", "雨", "雪",
                      "設定", "閉じる", "傘指数", "洗濯指数",
                      "時間ごとの予報", "雨雲レーダー", "空玉コレクション",
                      "作者を応援する", "空玉(そらだま)へようこそ",
                      "天気を取得できた日が、空玉になる",
                      "「自分の空」の天気を取得できたとき、端末の日付で1日1個の空玉が残ります",
                      "位置情報は現在地の天気と地点名の取得に使います。許可しなくても都市を選んで使えます"])
    func coreStringsAreTranslated(key: String) throws {
        let value = try #require(english(key), "「\(key)」の英訳が無い")
        #expect(value != key, "「\(key)」が英語版でも日本語のまま")
        // contains(where:) は rethrows なので、#expect の中に直接置くと throw 扱いになる
        let hasHiragana = value.contains { $0.isHiragana }
        #expect(!hasHiragana, "「\(key)」の訳にひらがなが混じっている: \(value)")
    }

    /// 二十四節気と月相は数が多く、追加時に訳を入れ忘れやすい。
    @Test("二十四節気はすべて英訳されている")
    func everySolarTermIsTranslated() throws {
        // `term.label` は端末言語で既に翻訳されるため、英語端末でも
        // 検証できるようString Catalogの日本語キーを明示して照合する。
        let entries: [(term: SolarTerm, key: String)] = [
            (.risshun, "立春"), (.usui, "雨水"), (.keichitsu, "啓蟄"),
            (.shunbun, "春分"), (.seimei, "清明"), (.kokuu, "穀雨"),
            (.rikka, "立夏"), (.shoman, "小満"), (.boshu, "芒種"),
            (.geshi, "夏至"), (.shosho, "小暑"), (.taisho, "大暑"),
            (.risshu, "立秋"), (.shosho2, "処暑"), (.hakuro, "白露"),
            (.shubun, "秋分"), (.kanro, "寒露"), (.soko, "霜降"),
            (.ritto, "立冬"), (.shosetsu, "小雪"), (.taisetsu, "大雪"),
            (.toji, "冬至"), (.shokan, "小寒"), (.daikan, "大寒"),
        ]
        #expect(entries.map { $0.term } == SolarTerm.allCases,
                "節気caseの追加・並べ替え時は翻訳キー対応も更新する")
        for (term, key) in entries {
            let value = try #require(english(key), "節気「\(key)」の英訳が無い")
            #expect(value != key, "節気「\(key)」が未翻訳")
            #expect(term.label == currentLocalization(key),
                    "節気 \(term.rawValue) が誤った翻訳キーに対応している")
        }
    }

    @Test("月相はすべて英訳されている")
    func everyMoonPhaseIsTranslated() throws {
        let entries: [(phase: MoonPhase, key: String)] = [
            (.newMoon, "新月"), (.waxingCrescent, "三日月"),
            (.firstQuarter, "上弦の月"), (.waxingGibbous, "十三夜"),
            (.fullMoon, "満月"), (.waningGibbous, "寝待月"),
            (.lastQuarter, "下弦の月"), (.waningCrescent, "有明月"),
        ]
        #expect(entries.map { $0.phase } == MoonPhase.allCases,
                "月相caseの追加・並べ替え時は翻訳キー対応も更新する")
        for (phase, key) in entries {
            let value = try #require(english(key), "月相「\(key)」の英訳が無い")
            #expect(value != key, "月相「\(key)」が未翻訳")
            #expect(phase.label == currentLocalization(key),
                    "月相 \(phase.rawValue) が誤った翻訳キーに対応している")
        }
    }

    @Test("天気の種類はすべて英訳されている")
    func everyWeatherKindIsTranslated() throws {
        let entries: [(kind: WeatherKind, key: String)] = [
            (.clear, "晴れ"), (.partlyCloudy, "晴れ時々くもり"),
            (.cloudy, "くもり"), (.fog, "霧"), (.drizzle, "霧雨"),
            (.rain, "雨"), (.snow, "雪"), (.thunderstorm, "雷雨"),
        ]
        #expect(entries.map { $0.kind } == WeatherKind.allCases,
                "天気caseの追加・並べ替え時は翻訳キー対応も更新する")
        for (kind, key) in entries {
            let value = try #require(english(key), "天気「\(key)」の英訳が無い")
            #expect(value != key, "天気「\(key)」が未翻訳")
            #expect(kind.label == currentLocalization(key),
                    "天気 \(kind.rawValue) が誤った翻訳キーに対応している")
        }
    }

    /// 地名検索の言語を "ja" で固定していたため、英語UIでも検索結果だけ
    /// 「ロンドン / イングランド / 英国」と日本語で出ていた。
    /// 端末の言語に追従すること、対応外の言語では英語に落ちることを固定する。
    @Test("地名検索の言語が端末に追従する")
    func geocodingLanguageFollowsDevice() {
        let language = GeocodingService.languageCode(for: Locale(identifier: "en_US"))
        #expect(language == "en")
        #expect(GeocodingService.languageCode(for: Locale(identifier: "ja_JP")) == "ja")
        #expect(GeocodingService.languageCode(for: Locale(identifier: "fr_FR")) == "fr")
        // Open-Meteo が対応しない言語は英語に落とす(日本語に落とすと読めない人が出る)
        #expect(GeocodingService.languageCode(for: Locale(identifier: "sv_SE")) == "en")
        #expect(GeocodingService.languageCode(for: Locale(identifier: "ko_KR")) == "en")
    }

    @Test("1.7.1で直した表示と通知に英訳がある")
    func release171StringsAreTranslated() throws {
        let keys = [
            "北", "北北東", "北東", "東北東", "東", "東南東", "南東", "南南東",
            "南", "南南西", "南西", "西南西", "西", "西北西", "北西", "北北西",
            "現在地", "視程 %@%@",
            "%@の風、秒速%lldメートル", "湿度%lldパーセント、%@",
            "☃️ まもなく雪の予報", "☔️ まもなく雨の予報",
            "☔️ 今日は傘の出番です", "🌂 折りたたみ傘があると安心",
            "☀️ 今日は傘なしで大丈夫そう",
            "%@では%@ごろから%@の見込みです(降水確率%lld%%)。",
            "%@の日中の降水確率は最大%lld%%。傘を持ってお出かけください。",
            "%@の日中の降水確率は最大%lld%%です。",
            "%@の日中の降水確率は最大%lld%%。よい一日を！",
            "🔮 連続%lld日の記録が今日で途切れそうです",
            "アプリを開くと今日の空玉を受け取れます。",
        ]
        for key in keys {
            let value = try #require(english(key), "「\(key)」の英訳が無い")
            #expect(value != key, "「\(key)」が英語版でも日本語のまま")
        }
    }

    @Test("成長改善の共有文に英訳がある")
    func growthShareStringsAreTranslated() throws {
        let keys = [
            "空を集める天気アプリ「空玉」",
            "毎日の空を、小さなガラス玉に残せる天気アプリです。",
            "今月の空を共有",
        ]
        for key in keys {
            let value = try #require(english(key), "「\(key)」の英訳が無い")
            #expect(value != key, "「\(key)」が英語版でも日本語のまま")
        }
    }

    @Test("今日の空玉カードの文言に英訳がある")
    func todayOrbCardStringsAreTranslated() throws {
        let keys = [
            "今日の空玉",
            "最初の空を集めました",
            "タップしてコレクションを見る",
            "空玉コレクションを開きます",
        ]
        for key in keys {
            let value = try #require(english(key), "「\(key)」の英訳が無い")
            #expect(value != key, "「\(key)」が英語版でも日本語のまま")
        }
    }

    @Test("ウィジェット案内の文言に英訳がある")
    func widgetGuideStringsAreTranslated() throws {
        let keys = [
            "ホーム画面に空玉を飾る",
            "アプリを開かないときも、今日の空玉と連続日数をひと目で見られます。",
            "ウィジェットの案内を閉じる",
            "追加方法を見る",
            "ホーム画面の何もない場所を長押しします",
            "「編集」または「＋」から「ウィジェットを追加」を選びます",
            "「空玉」を検索し、「今日の空玉」を追加します",
            "追加後にウィジェットをタップすると、空玉コレクションが開きます。",
        ]
        for key in keys {
            let value = try #require(english(key), "「\(key)」の英訳が無い")
            #expect(value != key, "「\(key)」が英語版でも日本語のまま")
        }
    }

    @Test("初回の地点選択に英訳がある")
    func primaryLocationChoiceStringsAreTranslated() throws {
        let keys = [
            "天気を取得できた日が、空玉になる",
            "「自分の空」の天気を取得できたとき、端末の日付で1日1個の空玉が残ります",
            "集めて、ホーム画面にも飾れる",
            "毎日の空をカレンダーで振り返り、\n今日の空玉をウィジェットで楽しめます",
            "現在地を使うか、都市を選んで\nあなたの空を決められます(あとから変更できます)",
            "現在地を使う",
            "現在地を取得しています…",
            "都市を選ぶ",
            "位置情報は現在地の天気と地点名の取得に使います。許可しなくても都市を選んで使えます",
            "最終更新: %@",
            "データ提供: Open-Meteo.com",
        ]
        for key in keys {
            let value = try #require(english(key), "「\(key)」の英訳が無い")
            #expect(value != key, "「\(key)」が英語版でも日本語のまま")
        }
    }


    @Test("空玉の記録条件と戻る操作に英訳がある")
    func orbRecordingGuideStringsAreTranslated() throws {
        let keys = [
            "空玉はいつ残る？",
            "アプリで自分の空の天気を取得できたとき、自動で記録されます。",
            "「自分の空」に設定した地点が対象です。別の都市を見るだけでは、記録する地点は変わりません。",
            "端末の日付で1日1個。同じ日に天気を取り直すと、その日の空玉が更新されます。",
            "通信に失敗したときや、保存済みの天気を表示するだけでは、新しい空玉は記録されません。自分の空の天気画面を下に引くと、もう一度取得できます。",
            "カレンダーの玉をタップすると、その日の空を確認できます。玉がある月は「この月をふりかえる」からまとめを見られます。",
            "天気に戻る",
            "コレクションを閉じて天気画面に戻ります",
        ]
        for key in keys {
            let value = try #require(english(key))
            #expect(value != key && !value.isEmpty)
        }
    }

    /// 時刻表示は書式ごと切り替わる必要がある。
    /// "H時" のような日本語専用の書式を直に指定していると、英語圏で "15時" と出てしまう。
    @Test("欠測と初回案内の操作を英語でも正しく表示する")
    func weatherAvailabilityAndOnboardingControlsAreTranslated() {
        #expect(english("傘指数、情報なし") == "Umbrella index, no data")
        #expect(english("洗濯指数、情報なし") == "Laundry index, no data")
        #expect(english("戻る") == "Back")
        #expect(english("%lld / 3") == "%lld / 3")
    }

    @Test("時刻の書式がロケールに追従する")
    func hourLabelFollowsLocale() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let label = date.hourLabel(in: tokyo)
        // 端末の言語がどちらであっても、数字は必ず含まれる
        let hasNumber = label.contains { $0.isNumber }
        #expect(hasNumber, "時刻に数字が無い: \(label)")
    }
}

private extension Character {
    var isHiragana: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x3040...0x309F).contains(scalar.value)
    }
}
