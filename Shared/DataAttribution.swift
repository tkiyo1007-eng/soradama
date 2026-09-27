import Foundation

/// 出典表示用のリンク。データ取得先や通信頻度には影響しない。
enum DataAttribution {
    static let openMeteo = URL(string: "https://open-meteo.com/")!
    static let openMeteoLicence = URL(string: "https://open-meteo.com/en/licence")!
    static let creativeCommons = URL(string: "https://creativecommons.org/licenses/by/4.0/")!
    static let geocoding = URL(string: "https://open-meteo.com/en/docs/geocoding-api")!
    static let geoNames = URL(string: "https://www.geonames.org/")!
    static let jmaRadar = URL(string: "https://www.jma.go.jp/bosai/nowc/")!
    static let jmaTerms = URL(string: "https://www.jma.go.jp/jma/kishou/info/coment.html")!
}
