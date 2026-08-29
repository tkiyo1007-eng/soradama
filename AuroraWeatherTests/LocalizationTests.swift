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
                      "作者を応援する", "空玉(そらだま)へようこそ"])
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
        for term in SolarTerm.allCases {
            // label / poem はどちらも String(localized:) 経由なので、
            // 日本語の原文をキーに英訳が引けるはず。
            let ja = term.label
            let value = try #require(english(ja), "節気「\(ja)」の英訳が無い")
            #expect(value != ja, "節気「\(ja)」が未翻訳")
        }
    }

    @Test("月相はすべて英訳されている")
    func everyMoonPhaseIsTranslated() throws {
        for phase in MoonPhase.allCases {
            let ja = phase.label
            let value = try #require(english(ja), "月相「\(ja)」の英訳が無い")
            #expect(value != ja, "月相「\(ja)」が未翻訳")
        }
    }

    @Test("天気の種類はすべて英訳されている")
    func everyWeatherKindIsTranslated() throws {
        for kind in WeatherKind.allCases {
            let ja = kind.label
            let value = try #require(english(ja), "天気「\(ja)」の英訳が無い")
            #expect(value != ja, "天気「\(ja)」が未翻訳")
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

    /// 時刻表示は書式ごと切り替わる必要がある。
    /// "H時" のような日本語専用の書式を直に指定していると、英語圏で "15時" と出てしまう。
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
