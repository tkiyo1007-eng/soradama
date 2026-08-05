import Foundation

/// 二十四節気。日本の暦で季節の移り変わりを示す24の区切り。
///
/// 春夏秋冬の4段階よりずっと細かく季節を刻めるので、
/// 「その日だけの空玉」を作るのにちょうどよい単位になる。
enum SolarTerm: String, Codable, CaseIterable {
    case risshun, usui, keichitsu, shunbun, seimei, kokuu          // 春
    case rikka, shoman, boshu, geshi, shosho, taisho               // 夏
    case risshu, shosho2, hakuro, shubun, kanro, soko              // 秋
    case ritto, shosetsu, taisetsu, toji, shokan, daikan           // 冬

    var label: String {
        switch self {
        case .risshun:  return "立春"
        case .usui:     return "雨水"
        case .keichitsu: return "啓蟄"
        case .shunbun:  return "春分"
        case .seimei:   return "清明"
        case .kokuu:    return "穀雨"
        case .rikka:    return "立夏"
        case .shoman:   return "小満"
        case .boshu:    return "芒種"
        case .geshi:    return "夏至"
        case .shosho:   return "小暑"
        case .taisho:   return "大暑"
        case .risshu:   return "立秋"
        case .shosho2:  return "処暑"
        case .hakuro:   return "白露"
        case .shubun:   return "秋分"
        case .kanro:    return "寒露"
        case .soko:     return "霜降"
        case .ritto:    return "立冬"
        case .shosetsu: return "小雪"
        case .taisetsu: return "大雪"
        case .toji:     return "冬至"
        case .shokan:   return "小寒"
        case .daikan:   return "大寒"
        }
    }

    /// その節気の意味を、空にまつわる一言で。
    var poem: String {
        switch self {
        case .risshun:  return "こよみの上では、今日から春です"
        case .usui:     return "雪が雨に変わるころ。空がゆるみます"
        case .keichitsu: return "土の中の虫も目を覚ますころ"
        case .shunbun:  return "昼と夜の長さが、ちょうど同じになる日"
        case .seimei:   return "空も草木も、すべてが清らかに明るいころ"
        case .kokuu:    return "穀物を育てる雨が降るころ"
        case .rikka:    return "こよみの上では、今日から夏です"
        case .shoman:   return "草木が生い茂り、天地に満ちるころ"
        case .boshu:    return "そろそろ梅雨の入り口です"
        case .geshi:    return "一年でいちばん、昼が長い日"
        case .shosho:   return "梅雨が明け、本格的な暑さが始まるころ"
        case .taisho:   return "一年でいちばん暑さがきびしいころ"
        case .risshu:   return "こよみの上では、今日から秋です"
        case .shosho2:  return "暑さがやわらぎ、風に秋を感じるころ"
        case .hakuro:   return "草に白い露が結ぶころ。空が高くなります"
        case .shubun:   return "昼と夜の長さが、ふたたび同じになる日"
        case .kanro:    return "露が冷たく感じられるころ"
        case .soko:     return "朝に霜が降りはじめるころ"
        case .ritto:    return "こよみの上では、今日から冬です"
        case .shosetsu: return "初雪の便りが届きはじめるころ"
        case .taisetsu: return "本格的に雪が降り積もるころ"
        case .toji:     return "一年でいちばん、夜が長い日"
        case .shokan:   return "寒さがいよいよ本番を迎えるころ"
        case .daikan:   return "一年でいちばん寒さがきびしいころ"
        }
    }

    /// 節気の玉に添える色。季節が進むにつれて移り変わる。
    var accent: (r: Double, g: Double, b: Double) {
        switch self {
        case .risshun, .usui, .keichitsu, .shunbun, .seimei, .kokuu:
            return (1.0, 0.72, 0.82)  // 春 — 桜色
        case .rikka, .shoman, .boshu, .geshi, .shosho, .taisho:
            return (0.45, 0.88, 0.75) // 夏 — 若葉と水
        case .risshu, .shosho2, .hakuro, .shubun, .kanro, .soko:
            return (1.0, 0.72, 0.42)  // 秋 — 実りと夕陽
        case .ritto, .shosetsu, .taisetsu, .toji, .shokan, .daikan:
            return (0.72, 0.88, 1.0)  // 冬 — 澄んだ氷
        }
    }

    /// その年の各節気のおおよその日付(月, 日)。
    /// 実際には年によって1日前後ずれるが、暦の計算式を持ち込むほどの
    /// 精度は必要ないので、国立天文台の暦要項でよく使われる代表日を用いる。
    private static let approximateDates: [(SolarTerm, Int, Int)] = [
        (.risshun, 2, 4), (.usui, 2, 19), (.keichitsu, 3, 6), (.shunbun, 3, 21),
        (.seimei, 4, 5), (.kokuu, 4, 20), (.rikka, 5, 6), (.shoman, 5, 21),
        (.boshu, 6, 6), (.geshi, 6, 21), (.shosho, 7, 7), (.taisho, 7, 23),
        (.risshu, 8, 8), (.shosho2, 8, 23), (.hakuro, 9, 8), (.shubun, 9, 23),
        (.kanro, 10, 8), (.soko, 10, 24), (.ritto, 11, 7), (.shosetsu, 11, 22),
        (.taisetsu, 12, 7), (.toji, 12, 22), (.shokan, 1, 6), (.daikan, 1, 20),
    ]

    /// その日が節気にあたるなら返す。
    static func on(_ date: Date) -> SolarTerm? {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return approximateDates.first { $0.1 == month && $0.2 == day }?.0
    }
}

// MARK: - 月の満ち欠け

/// 月相。夜の空玉に映すために使う。
enum MoonPhase: String, Codable, CaseIterable {
    case newMoon, waxingCrescent, firstQuarter, waxingGibbous
    case fullMoon, waningGibbous, lastQuarter, waningCrescent

    var label: String {
        switch self {
        case .newMoon:         return "新月"
        case .waxingCrescent:  return "三日月"
        case .firstQuarter:    return "上弦の月"
        case .waxingGibbous:   return "十三夜"
        case .fullMoon:        return "満月"
        case .waningGibbous:   return "寝待月"
        case .lastQuarter:     return "下弦の月"
        case .waningCrescent:  return "有明月"
        }
    }

    /// 満ちている割合(0 = 新月、1 = 満月)。玉に描く月の形に使う。
    var illumination: Double {
        switch self {
        case .newMoon:        return 0.0
        case .waxingCrescent: return 0.25
        case .firstQuarter:   return 0.5
        case .waxingGibbous:  return 0.75
        case .fullMoon:       return 1.0
        case .waningGibbous:  return 0.75
        case .lastQuarter:    return 0.5
        case .waningCrescent: return 0.25
        }
    }

    /// 満ちていく側か(欠けていく側なら false)。月の影の向きが左右で変わる。
    var isWaxing: Bool {
        switch self {
        case .newMoon, .waxingCrescent, .firstQuarter, .waxingGibbous: return true
        default: return false
        }
    }

    /// 朔望月(29.530588日)を基準に、既知の新月からの経過で求める。
    /// 分単位の精度は要らないので、平均朔望月による近似で十分。
    static func on(_ date: Date) -> MoonPhase {
        // 2000年1月6日 18:14 UTC が新月
        let knownNewMoon = Date(timeIntervalSince1970: 947182440)
        let synodicMonth: Double = 29.530588853
        let days = date.timeIntervalSince(knownNewMoon) / 86400
        var age = days.truncatingRemainder(dividingBy: synodicMonth)
        if age < 0 { age += synodicMonth }

        let phase = age / synodicMonth // 0..<1
        switch phase {
        case ..<0.0325:  return .newMoon
        case ..<0.2175:  return .waxingCrescent
        case ..<0.2825:  return .firstQuarter
        case ..<0.4675:  return .waxingGibbous
        case ..<0.5325:  return .fullMoon
        case ..<0.7175:  return .waningGibbous
        case ..<0.7825:  return .lastQuarter
        case ..<0.9675:  return .waningCrescent
        default:         return .newMoon
        }
    }
}
