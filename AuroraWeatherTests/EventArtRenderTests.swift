import Testing
import SwiftUI
@testable import AuroraWeather

/// App Store のアプリ内イベント画像の素材として、アプリと同じ描画の空玉を書き出す。
/// 通常のテスト実行では何もしない。環境変数に出力先を渡したときだけ書き出す。
@MainActor
struct EventArtRenderTests {
    @Test("イベント画像用のハロウィンの空玉を書き出す（指定時のみ）")
    func renderHalloweenOrb() async throws {
        guard let output = ProcessInfo.processInfo.environment["SORADAMA_RENDER_EVENT_ORB"] else { return }
        let orb = DailyOrb(
            dateKey: "2026-10-15",
            kind: .partlyCloudy,
            tempMax: 20,
            tempMin: 14,
            humidity: 60,
            precipProbability: nil,
            placeName: "",
            timeOfDay: .dusk
        )
        let size: CGFloat = 300
        try await write(
            OrbView(orb: orb, size: size, animated: false)
                .halloweenOrbAccent(true, size: size),
            to: output
        )
    }

    /// 冬のイベント用。SORADAMA_RENDER_WINTER_ORBS に出力先のフォルダを渡す。
    /// 立冬の日の玉・満月の夜の玉は、アプリが実際に作る特別な玉と同じ日付と時間帯で描く。
    @Test("イベント画像用の冬の空玉を書き出す（指定時のみ）")
    func renderWinterOrbs() async throws {
        guard let folder = ProcessInfo.processInfo.environment["SORADAMA_RENDER_WINTER_ORBS"] else { return }
        let size: CGFloat = 300
        let ritto = DailyOrb(
            dateKey: "2026-11-07", kind: .clear, tempMax: 15, tempMin: 7, humidity: 55,
            precipProbability: nil, placeName: "", timeOfDay: .dawn
        )
        let fullMoon = DailyOrb(
            dateKey: "2026-11-24", kind: .clear, tempMax: 12, tempMin: 4, humidity: 55,
            precipProbability: nil, placeName: "", timeOfDay: .night
        )
        let christmas = DailyOrb(
            dateKey: "2026-12-10", kind: .clear, tempMax: 9, tempMin: 2, humidity: 55,
            precipProbability: nil, placeName: "", timeOfDay: .night
        )
        #expect(ritto.solarTerm == .ritto)
        #expect(fullMoon.moonPhase == .fullMoon)
        try await write(OrbView(orb: ritto, size: size, animated: false), to: "\(folder)/orb-ritto.png")
        try await write(OrbView(orb: fullMoon, size: size, animated: false), to: "\(folder)/orb-fullmoon.png")
        try await write(
            OrbView(orb: christmas, size: size, animated: false)
                .seasonalOrbAccent(.christmas2026, size: size),
            to: "\(folder)/orb-christmas.png"
        )
    }

    /// 冬至から大寒のイベント用。SORADAMA_RENDER_MIDWINTER_ORBS に出力先のフォルダを渡す。
    @Test("イベント画像用の冬至・満月・大寒の空玉を書き出す（指定時のみ）")
    func renderMidwinterOrbs() async throws {
        guard let folder = ProcessInfo.processInfo.environment["SORADAMA_RENDER_MIDWINTER_ORBS"] else { return }
        let size: CGFloat = 300
        let toji = DailyOrb(
            dateKey: "2026-12-22", kind: .clear, tempMax: 8, tempMin: 1, humidity: 50,
            precipProbability: nil, placeName: "", timeOfDay: .dusk
        )
        let fullMoon = DailyOrb(
            dateKey: "2026-12-24", kind: .clear, tempMax: 7, tempMin: 0, humidity: 50,
            precipProbability: nil, placeName: "", timeOfDay: .night
        )
        let daikan = DailyOrb(
            dateKey: "2027-01-20", kind: .clear, tempMax: 4, tempMin: -2, humidity: 45,
            precipProbability: nil, placeName: "", timeOfDay: .dawn
        )
        #expect(toji.solarTerm == .toji)
        #expect(fullMoon.moonPhase == .fullMoon)
        #expect(daikan.solarTerm == .daikan)
        try await write(OrbView(orb: toji, size: size, animated: false), to: "\(folder)/orb-toji.png")
        try await write(OrbView(orb: fullMoon, size: size, animated: false), to: "\(folder)/orb-fullmoon-dec.png")
        try await write(OrbView(orb: daikan, size: size, animated: false), to: "\(folder)/orb-daikan.png")
    }

    /// ImageRenderer は大きなぼかしの影を段状に描くため、画面と同じ経路
    /// (ウィンドウに載せて drawHierarchy)で書き出す。背景は透明にする。
    private func write(_ content: some View, to output: String) async throws {
        let host = UIHostingController(rootView: content.frame(width: 600, height: 600))
        host.view.backgroundColor = .clear
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 600)
        let window = UIWindow(frame: bounds)
        window.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = bounds
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        let data = try #require(image.pngData())
        try data.write(to: URL(fileURLWithPath: output))
    }
}
