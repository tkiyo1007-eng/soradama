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
        case .risshun:  return String(localized: "立春")
        case .usui:     return String(localized: "雨水")
        case .keichitsu: return String(localized: "啓蟄")
        case .shunbun:  return String(localized: "春分")
        case .seimei:   return String(localized: "清明")
        case .kokuu:    return String(localized: "穀雨")
        case .rikka:    return String(localized: "立夏")
        case .shoman:   return String(localized: "小満")
        case .boshu:    return String(localized: "芒種")
        case .geshi:    return String(localized: "夏至")
        case .shosho:   return String(localized: "小暑")
        case .taisho:   return String(localized: "大暑")
        case .risshu:   return String(localized: "立秋")
        case .shosho2:  return String(localized: "処暑")
        case .hakuro:   return String(localized: "白露")
        case .shubun:   return String(localized: "秋分")
        case .kanro:    return String(localized: "寒露")
        case .soko:     return String(localized: "霜降")
        case .ritto:    return String(localized: "立冬")
        case .shosetsu: return String(localized: "小雪")
        case .taisetsu: return String(localized: "大雪")
        case .toji:     return String(localized: "冬至")
        case .shokan:   return String(localized: "小寒")
        case .daikan:   return String(localized: "大寒")
        }
    }

    /// その節気の意味を、空にまつわる一言で。
    var poem: String {
        switch self {
        case .risshun:  return String(localized: "こよみの上では、今日から春です")
        case .usui:     return String(localized: "雪が雨に変わるころ。空がゆるみます")
        case .keichitsu: return String(localized: "土の中の虫も目を覚ますころ")
        case .shunbun:  return String(localized: "昼と夜の長さが、ちょうど同じになる日")
        case .seimei:   return String(localized: "空も草木も、すべてが清らかに明るいころ")
        case .kokuu:    return String(localized: "穀物を育てる雨が降るころ")
        case .rikka:    return String(localized: "こよみの上では、今日から夏です")
        case .shoman:   return String(localized: "草木が生い茂り、天地に満ちるころ")
        case .boshu:    return String(localized: "そろそろ梅雨の入り口です")
        case .geshi:    return String(localized: "一年でいちばん、昼が長い日")
        case .shosho:   return String(localized: "梅雨が明け、本格的な暑さが始まるころ")
        case .taisho:   return String(localized: "一年でいちばん暑さがきびしいころ")
        case .risshu:   return String(localized: "こよみの上では、今日から秋です")
        case .shosho2:  return String(localized: "暑さがやわらぎ、風に秋を感じるころ")
        case .hakuro:   return String(localized: "草に白い露が結ぶころ。空が高くなります")
        case .shubun:   return String(localized: "昼と夜の長さが、ふたたび同じになる日")
        case .kanro:    return String(localized: "露が冷たく感じられるころ")
        case .soko:     return String(localized: "朝に霜が降りはじめるころ")
        case .ritto:    return String(localized: "こよみの上では、今日から冬です")
        case .shosetsu: return String(localized: "初雪の便りが届きはじめるころ")
        case .taisetsu: return String(localized: "本格的に雪が降り積もるころ")
        case .toji:     return String(localized: "一年でいちばん、夜が長い日")
        case .shokan:   return String(localized: "寒さがいよいよ本番を迎えるころ")
        case .daikan:   return String(localized: "一年でいちばん寒さがきびしいころ")
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

    /// 各節気に対応する太陽黄経(度)。立春の 315 度から 15 度ずつ進む。
    var solarLongitude: Double {
        switch self {
        case .risshun:  return 315
        case .usui:     return 330
        case .keichitsu: return 345
        case .shunbun:  return 0
        case .seimei:   return 15
        case .kokuu:    return 30
        case .rikka:    return 45
        case .shoman:   return 60
        case .boshu:    return 75
        case .geshi:    return 90
        case .shosho:   return 105
        case .taisho:   return 120
        case .risshu:   return 135
        case .shosho2:  return 150
        case .hakuro:   return 165
        case .shubun:   return 180
        case .kanro:    return 195
        case .soko:     return 210
        case .ritto:    return 225
        case .shosetsu: return 240
        case .taisetsu: return 255
        case .toji:     return 270
        case .shokan:   return 285
        case .daikan:   return 300
        }
    }

    /// その日が節気にあたるなら返す。
    ///
    /// 節気は「太陽黄経が15度の倍数になる瞬間」で決まり、年によって日付が1日前後ずれる。
    /// 以前は代表日を固定値で持っていたためズレを取りこぼしていたので、
    /// 実際に黄経を計算して判定するようにした。
    static func on(_ date: Date, timeZone: TimeZone = .current) -> SolarTerm? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // その日の始まりと終わり(ローカル時刻)
        guard let dayStart = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: date)),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        // 節気の瞬間がこの一日の中に入っていれば、その日が節気の日
        let startLongitude = Astronomy.solarLongitude(dayStart)
        let endLongitude = Astronomy.solarLongitude(dayEnd)

        for term in SolarTerm.allCases {
            let target = term.solarLongitude
            // 15度刻みの境界をこの一日でまたいだか(0度をまたぐ春分も扱えるようにする)
            let crossed: Bool
            if startLongitude <= endLongitude {
                crossed = startLongitude < target && target <= endLongitude
            } else {
                // 360→0 をまたぐ日
                crossed = target > startLongitude || target <= endLongitude
            }
            if crossed { return term }
        }
        return nil
    }
}

// MARK: - 月の満ち欠け

/// 月相。夜の空玉に映すために使う。
enum MoonPhase: String, Codable, CaseIterable {
    case newMoon, waxingCrescent, firstQuarter, waxingGibbous
    case fullMoon, waningGibbous, lastQuarter, waningCrescent

    var label: String {
        switch self {
        case .newMoon:         return String(localized: "新月")
        case .waxingCrescent:  return String(localized: "三日月")
        case .firstQuarter:    return String(localized: "上弦の月")
        case .waxingGibbous:   return String(localized: "十三夜")
        case .fullMoon:        return String(localized: "満月")
        case .waningGibbous:   return String(localized: "寝待月")
        case .lastQuarter:     return String(localized: "下弦の月")
        case .waningCrescent:  return String(localized: "有明月")
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

    /// 月と太陽の黄経差から求める。
    ///
    /// 以前は平均朔望月による近似だったため、実際の満月と半日ほどずれることがあった。
    /// 黄経差 0 度が新月、90 度が上弦、180 度が満月、270 度が下弦。
    static func on(_ date: Date) -> MoonPhase {
        let angle = Astronomy.moonPhaseAngle(date)
        // 各相の中心から ±11.25 度(朔望月のおよそ 1/32)を「その相」とみなす
        switch angle {
        case ..<11.25:   return .newMoon
        case ..<78.75:   return .waxingCrescent
        case ..<101.25:  return .firstQuarter
        case ..<168.75:  return .waxingGibbous
        case ..<191.25:  return .fullMoon
        case ..<258.75:  return .waningGibbous
        case ..<281.25:  return .lastQuarter
        case ..<348.75:  return .waningCrescent
        default:         return .newMoon
        }
    }

    /// 満ちている割合を黄経差から連続値で求める(0 = 新月、1 = 満月)。
    /// 玉に描く月の形はこの値を使うので、相の区分より滑らかに変化する。
    static func illumination(at date: Date) -> Double {
        let angle = Astronomy.moonPhaseAngle(date) * .pi / 180
        return (1 - cos(angle)) / 2
    }
}
