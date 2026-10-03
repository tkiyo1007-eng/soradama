import Testing
import SwiftUI
@testable import AuroraWeather

/// App Store のアプリ内イベント画像の素材として、アプリと同じ描画のハロウィンの空玉を書き出す。
/// 通常のテスト実行では何もしない。環境変数 SORADAMA_RENDER_EVENT_ORB に出力先を渡したときだけ書き出す。
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
        let view = OrbView(orb: orb, size: size, animated: false)
            .halloweenOrbAccent(true, size: size)
            .frame(width: 600, height: 600)
        // ImageRenderer は大きなぼかしの影を段状に描くため、画面と同じ経路
        // (ウィンドウに載せて drawHierarchy)で書き出す。背景は透明にする。
        let host = UIHostingController(rootView: view)
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
