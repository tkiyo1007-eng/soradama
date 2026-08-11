import SwiftUI
import MapKit

// MARK: - 雨雲レーダーシート

struct RadarSheet: View {
    let place: SavedPlace
    /// 地点のタイムゾーン(コマの時刻表示に使う。端末TZだと海外都市でズレる)
    var timeZone: TimeZone = .current
    @Environment(\.dismiss) private var dismiss

    @State private var frames: [RadarFrame] = []
    @State private var frameIndex = 0
    @State private var isPlaying = false
    @State private var loadFailed = false

    private var currentFrame: RadarFrame? {
        frames.indices.contains(frameIndex) ? frames[frameIndex] : nil
    }

    /// 気象庁ナウキャストは日本周辺しか覆っていない
    private var isCovered: Bool {
        RadarService.isCovered(latitude: place.latitude, longitude: place.longitude)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                RadarMapView(
                    latitude: place.latitude,
                    longitude: place.longitude,
                    frame: currentFrame
                )
                .ignoresSafeArea(edges: .bottom)

                if !isCovered {
                    outOfRangeBanner
                } else if loadFailed {
                    failedBanner
                } else if frames.isEmpty {
                    ProgressView("レーダーを読み込み中…")
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.bottom, 40)
                } else {
                    controls
                }
            }
            .navigationTitle("雨雲レーダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                // 公共データ利用規約では出典の明示が求められている。
                // ただし提供範囲外では気象庁のデータを一枚も使っていないので出さない。
                if isCovered {
                    Text("出典: 気象庁 高解像度降水ナウキャスト")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                }
            }
        }
        .task { await load() }
        .task(id: isPlaying) {
            guard isPlaying else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 650_000_000)
                if Task.isCancelled { return }
                guard !frames.isEmpty else { continue }
                frameIndex = (frameIndex + 1) % frames.count
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if let frame = currentFrame {
                HStack(spacing: 8) {
                    Text(frame.date.timeLabel(in: timeZone))
                        .font(.headline.monospacedDigit())
                    Text(frame.isForecast ? "予測" : "実況")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (frame.isForecast ? Color.orange : Color.blue).opacity(0.25),
                            in: Capsule()
                        )
                }
            }
            HStack(spacing: 14) {
                Button {
                    isPlaying.toggle()
                    Haptics.selection()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .background(.thinMaterial, in: Circle())
                }
                .accessibilityLabel(isPlaying ? "一時停止" : "再生")

                if frames.count > 1 {
                    Slider(
                        value: Binding(
                            get: { Double(frameIndex) },
                            set: { frameIndex = Int($0.rounded()); isPlaying = false }
                        ),
                        in: 0...Double(frames.count - 1),
                        step: 1
                    )
                    .accessibilityLabel("時刻の選択")
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var outOfRangeBanner: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe.asia.australia")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("この地域の雨雲レーダーはありません")
                .font(.callout.weight(.medium))
            Text("雨雲レーダーは気象庁のデータを使っているため、\n日本とその周辺だけに対応しています")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 40)
    }

    private var failedBanner: some View {
        VStack(spacing: 10) {
            Text("レーダーデータを取得できませんでした")
                .font(.callout)
            Button("再試行") {
                loadFailed = false
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 40)
    }

    private func load() async {
        guard isCovered else { return }
        do {
            frames = try await RadarService().fetchFrames()
            // まれに空配列が正常応答として返ることがあり、その場合スピナーが
            // 永久に消えないため失敗として扱う
            if frames.isEmpty { loadFailed = true }
            // 最新の実況フレームから開始
            frameIndex = max(frames.lastIndex(where: { !$0.isForecast }) ?? 0, 0)
        } catch {
            loadFailed = true
        }
    }
}

// MARK: - MapKit ラッパー

/// 気象庁ナウキャストのタイルを供給するオーバーレイ。
///
/// 気象庁はズームレベル4・6・8・10 の**偶数だけ**を配信していて、
/// 奇数を要求すると 200 が返るのに中身は完全に透明な PNG になる。
/// 実測で確認した挙動なので、奇数を要求されたら1段下の偶数タイルへ読み替える
/// (地図側は返ってきたタイルを引き伸ばして描いてくれる)。
final class JMANowcastTileOverlay: MKTileOverlay {
    private let baseTime: String
    private let validTime: String

    init(frame: RadarFrame) {
        baseTime = frame.baseTime
        validTime = frame.validTime
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: 256, height: 256)
        canReplaceMapContent = false
        minimumZ = 4
        maximumZ = 10
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        var z = path.z
        var x = path.x
        var y = path.y
        if !z.isMultiple(of: 2) {
            z -= 1
            x /= 2
            y /= 2
        }
        let string = "https://www.jma.go.jp/bosai/jmatile/data/nowc/"
            + "\(baseTime)/none/\(validTime)/surf/hrpns/\(z)/\(x)/\(y).png"
        return URL(string: string)!
    }
}

struct RadarMapView: UIViewRepresentable {
    let latitude: Double
    let longitude: Double
    let frame: RadarFrame?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 2.4, longitudeDelta: 2.4)
        )

        let pin = MKPointAnnotation()
        pin.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        map.addAnnotation(pin)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        guard context.coordinator.currentFrameID != frame?.id else { return }
        context.coordinator.currentFrameID = frame?.id

        map.removeOverlays(map.overlays)
        if let frame {
            map.addOverlay(JMANowcastTileOverlay(frame: frame), level: .aboveRoads)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var currentFrameID: String?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tile)
                renderer.alpha = 0.7
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
