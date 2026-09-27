import Foundation
import Testing
@testable import AuroraWeather

struct DataAttributionTests {
    private let destinations: [(url: URL, expected: String)] = [
        (DataAttribution.openMeteo, "https://open-meteo.com/"),
        (DataAttribution.openMeteoLicence, "https://open-meteo.com/en/licence"),
        (DataAttribution.creativeCommons, "https://creativecommons.org/licenses/by/4.0/"),
        (DataAttribution.geocoding, "https://open-meteo.com/en/docs/geocoding-api"),
        (DataAttribution.geoNames, "https://www.geonames.org/"),
        (DataAttribution.jmaRadar, "https://www.jma.go.jp/bosai/nowc/"),
        (DataAttribution.jmaTerms, "https://www.jma.go.jp/jma/kishou/info/coment.html"),
    ]

    @Test("出典のリンクは指定した提供元と利用条件を指す")
    func linksKeepTheirApprovedDestinations() {
        for destination in destinations {
            #expect(destination.url.absoluteString == destination.expected)
        }
    }

    @Test("出典のリンクはHTTPSで、認証情報や追加パラメータを含まない")
    func linksDoNotCarryCredentialsOrParameters() throws {
        for destination in destinations {
            let components = try #require(URLComponents(url: destination.url, resolvingAgainstBaseURL: false))
            let expected = try #require(URLComponents(string: destination.expected))
            #expect(components.scheme == "https")
            #expect(components.host == expected.host)
            #expect(components.user == nil)
            #expect(components.password == nil)
            #expect(components.port == nil)
            #expect(components.query == nil)
            #expect(components.fragment == nil)
        }
    }

    @Test("出典と利用条件の表示文に英訳が同梱される")
    func attributionStringsAreTranslated() throws {
        let path = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let keys = [
            "データの出典と利用条件", "天気データ: Open-Meteo", "都市情報: Open-Meteo",
            "地点データ: GeoNames", "ライセンス: CC BY 4.0", "Open-Meteoの利用条件",
            "雨雲レーダー: 気象庁", "気象庁の利用規約", "天気と地点データ",
            "雨雲レーダー（日本周辺）", "アプリ内での加工",
            "空玉では提供データを単位換算し、グラフ・各種指標・空玉として表示しています。提供元による推奨を示すものではありません。",
            "気象庁の高解像度降水ナウキャストを地図に重ねて表示しています。",
        ]
        for key in keys {
            let translation = bundle.localizedString(forKey: key, value: "__missing__", table: nil)
            #expect(translation != "__missing__")
            #expect(translation != key)
        }
    }
}
