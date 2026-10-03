import Testing
import SwiftUI
@testable import AuroraWeather

/// App Store のスクリーンショット用に、アプリと同じ描画の空玉を背景透明の PNG で書き出す。
/// 通常のテスト実行では何もしない。環境変数 SORADAMA_RENDER_STORE_ORBS に出力先フォルダを渡したときだけ動く。
@MainActor
struct StoreArtRenderTests {
    private struct Sample {
        let name: String
        let orb: DailyOrb
    }

    private static let samples: [Sample] = [
        Sample(name: "clear-day", orb: DailyOrb(
            dateKey: "2026-07-20", kind: .clear, tempMax: 31, tempMin: 24, humidity: 55,
            precipProbability: 0, placeName: "", timeOfDay: .day)),
        Sample(name: "sunset", orb: DailyOrb(
            dateKey: "2026-09-22", kind: .partlyCloudy, tempMax: 24, tempMin: 18, humidity: 60,
            precipProbability: 10, placeName: "", timeOfDay: .dusk)),
        Sample(name: "full-moon-night", orb: DailyOrb(
            dateKey: "2026-09-26", kind: .clear, tempMax: 22, tempMin: 16, humidity: 60,
            precipProbability: 0, placeName: "", timeOfDay: .night)),
        Sample(name: "rain", orb: DailyOrb(
            dateKey: "2026-06-15", kind: .rain, tempMax: 21, tempMin: 17, humidity: 90,
            precipProbability: 90, placeName: "", timeOfDay: .day)),
        Sample(name: "snow", orb: DailyOrb(
            dateKey: "2026-01-20", kind: .snow, tempMax: 2, tempMin: -3, humidity: 80,
            precipProbability: 70, placeName: "", timeOfDay: .day)),
        Sample(name: "dawn", orb: DailyOrb(
            dateKey: "2026-04-10", kind: .clear, tempMax: 18, tempMin: 9, humidity: 50,
            precipProbability: 0, placeName: "", timeOfDay: .dawn)),
        Sample(name: "crystal", orb: DailyOrb(
            dateKey: "2026-08-12", kind: .thunderstorm, tempMax: 30, tempMin: 25, humidity: 80,
            precipProbability: 80, placeName: "", isMilestone: true, timeOfDay: .night)),
    ]

    @Test("ストア画像用の空玉を書き出す（指定時のみ）")
    func renderStoreOrbs() async throws {
        guard let folder = ProcessInfo.processInfo.environment["SORADAMA_RENDER_STORE_ORBS"] else { return }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for sample in Self.samples {
            let data = try await render(OrbView(orb: sample.orb, size: 300, animated: false))
            try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(sample.name).png"))
        }
    }

    /// 画面と同じ経路(ウィンドウに載せて drawHierarchy)で、背景透明のまま書き出す。
    private func render(_ content: some View) async throws -> Data {
        let side: CGFloat = 400
        let host = UIHostingController(rootView: content.frame(width: side, height: side))
        host.view.backgroundColor = .clear
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let window = UIWindow(frame: bounds)
        window.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = bounds
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        return try #require(image.pngData())
    }
}
