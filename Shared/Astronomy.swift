import Foundation

/// 太陽と月の黄経を求める天文計算。
///
/// 二十四節気は「太陽黄経が15度の倍数になる瞬間」、月相は「月と太陽の黄経差」で
/// 決まる。以前はどちらも固定日付・平均朔望月による近似で済ませていたが、
/// 実際の節気は年によって1日前後ずれ、月相も半日ほどずれることがあったため、
/// 天文計算に置き換えた。
///
/// 式は Jean Meeus "Astronomical Algorithms" の簡略版。秒単位の精度は要らないので
/// 主要項のみを採用している(黄経の誤差はおよそ 0.01 度／月は 0.3 度程度)。
enum Astronomy {

    // MARK: - 基本

    /// ユリウス世紀(J2000.0 からの経過)
    private static func julianCentury(_ date: Date) -> Double {
        // Unix エポック(1970-01-01)のユリウス日は 2440587.5
        let julianDay = date.timeIntervalSince1970 / 86400 + 2440587.5
        return (julianDay - 2451545.0) / 36525
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    /// 0..<360 に正規化する
    static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    // MARK: - 太陽

    /// 見かけの太陽黄経(度)
    static func solarLongitude(_ date: Date) -> Double {
        let t = julianCentury(date)

        // 平均黄経
        let l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
        // 平均近点角
        let m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t
        let mRad = radians(m)

        // 中心差
        let c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(mRad)
            + (0.019993 - 0.000101 * t) * sin(2 * mRad)
            + 0.000289 * sin(3 * mRad)

        let trueLongitude = l0 + c

        // 章動と光行差の補正(見かけの黄経にする)
        let omega = 125.04 - 1934.136 * t
        let apparent = trueLongitude - 0.00569 - 0.00478 * sin(radians(omega))
        return normalizedDegrees(apparent)
    }

    // MARK: - 月

    /// 月の黄経(度)。主要な摂動項のみを採用した近似。
    static func lunarLongitude(_ date: Date) -> Double {
        let t = julianCentury(date)

        // 月の平均黄経
        let lPrime = 218.3164477 + 481267.88123421 * t - 0.0015786 * t * t
        // 月の平均離角
        let d = 297.8501921 + 445267.1114034 * t - 0.0018819 * t * t
        // 太陽の平均近点角
        let m = 357.5291092 + 35999.0502909 * t - 0.0001536 * t * t
        // 月の平均近点角
        let mPrime = 134.9633964 + 477198.8675055 * t + 0.0087414 * t * t
        // 月の緯度引数
        let f = 93.2720950 + 483202.0175233 * t - 0.0036539 * t * t

        let dR = radians(d), mR = radians(m), mpR = radians(mPrime), fR = radians(f)

        // 黄経の主要摂動項(度)
        var correction = 6.288774 * sin(mpR)
        correction += 1.274027 * sin(2 * dR - mpR)
        correction += 0.658314 * sin(2 * dR)
        correction += 0.213618 * sin(2 * mpR)
        correction -= 0.185116 * sin(mR)
        correction -= 0.114332 * sin(2 * fR)
        correction += 0.058793 * sin(2 * dR - 2 * mpR)
        correction += 0.057066 * sin(2 * dR - mR - mpR)
        correction += 0.053322 * sin(2 * dR + mpR)
        correction += 0.045758 * sin(2 * dR - mR)
        correction -= 0.040923 * sin(mR - mpR)
        correction -= 0.034720 * sin(dR)
        correction -= 0.030383 * sin(mR + mpR)
        correction += 0.015327 * sin(2 * dR - 2 * fR)
        correction -= 0.012528 * sin(mpR + 2 * fR)
        correction += 0.010980 * sin(mpR - 2 * fR)
        correction += 0.010675 * sin(4 * dR - mpR)
        correction += 0.010034 * sin(3 * mpR)

        return normalizedDegrees(lPrime + correction)
    }

    /// 月と太陽の黄経差(度)。0 が新月、90 が上弦、180 が満月、270 が下弦。
    static func moonPhaseAngle(_ date: Date) -> Double {
        normalizedDegrees(lunarLongitude(date) - solarLongitude(date))
    }

    // MARK: - 節気の時刻を求める

    /// 太陽黄経が `targetLongitude` に達する瞬間を、`around` の前後 `windowDays` 日から二分探索で求める。
    /// 見つからない場合は nil。
    static func timeOfSolarLongitude(
        _ targetLongitude: Double,
        around: Date,
        windowDays: Double = 12
    ) -> Date? {
        // 目的の黄経までの差を -180..<180 で表す。これが 0 を跨ぐ点を探す
        func delta(_ date: Date) -> Double {
            var diff = solarLongitude(date) - targetLongitude
            diff = diff.truncatingRemainder(dividingBy: 360)
            if diff > 180 { diff -= 360 }
            if diff < -180 { diff += 360 }
            return diff
        }

        var low = around.addingTimeInterval(-windowDays * 86400)
        var high = around.addingTimeInterval(windowDays * 86400)
        guard delta(low) < 0, delta(high) > 0 else { return nil }

        // 太陽黄経は単調増加なので、単純な二分探索で十分
        for _ in 0..<60 {
            let mid = Date(timeIntervalSince1970: (low.timeIntervalSince1970 + high.timeIntervalSince1970) / 2)
            if delta(mid) < 0 { low = mid } else { high = mid }
        }
        return low
    }
}
