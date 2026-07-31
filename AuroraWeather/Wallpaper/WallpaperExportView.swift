import SwiftUI
import Photos

/// 「今日の空」をロック画面用の壁紙として書き出す機能。
/// アプリ内の演出をそのまま持ち出せるようにすることで、日常的に眺める
/// ロック画面という場所を通じて、そらだまが人の目に触れる機会を増やす狙い。
struct WallpaperExportView: View {
    @Environment(\.dismiss) private var dismiss
    let placeName: String
    let weather: WeatherBundle
    let degrees: (Double) -> String
    let orb: DailyOrb?

    @State private var saveState: SaveState = .idle
    /// 書き出し用の高解像度画像。1242×2688 のレンダリングは重いので、
    /// 画面表示時に一度だけ作って保存・共有で使い回す
    /// (ShareLink は body の評価ごとに item を要求するため、都度生成すると画面がカクつく)。
    @State private var exportImage: UIImage?

    private enum SaveState: Equatable {
        case idle, saving, saved, denied, failed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    GeometryReader { proxy in
                        WallpaperComposition(
                            placeName: placeName,
                            weather: weather,
                            degrees: degrees,
                            orb: orb
                        )
                        .frame(width: proxy.size.width, height: proxy.size.width * wallpaperAspect)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .aspectRatio(1 / wallpaperAspect, contentMode: .fit)
                    .padding(.horizontal, 32)

                    statusLabel

                    HStack(spacing: 14) {
                        Button {
                            save()
                        } label: {
                            Label("壁紙を保存", systemImage: "square.and.arrow.down")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.white.opacity(0.16), in: Capsule())
                        }
                        .disabled(saveState == .saving)

                        ShareLink(item: shareImage, preview: SharePreview("今日の空", image: shareImage)) {
                            Label("共有", systemImage: "square.and.arrow.up")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.white.opacity(0.16), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)
                }
                .padding(.top, 24)
            }
            .navigationTitle("今日の空を壁紙に")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .task {
                // 保存・共有どちらでも使える画像を、画面を開いた時点で一度だけ用意しておく
                if exportImage == nil {
                    exportImage = makeExportImage()
                }
            }
        }
    }

    private let wallpaperAspect: CGFloat = 2688.0 / 1242.0

    @ViewBuilder
    private var statusLabel: some View {
        switch saveState {
        case .idle:
            Text("ロック画面・ホーム画面用の壁紙として保存できます")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        case .saving:
            Text("保存しています…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        case .saved:
            Text("写真に保存しました")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.55, green: 0.85, blue: 0.6))
        case .denied:
            Text("設定アプリで写真へのアクセスを許可してください")
                .font(.caption)
                .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.5))
        case .failed:
            Text("保存に失敗しました。もう一度お試しください")
                .font(.caption)
                .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.5))
        }
    }

    /// 高解像度の壁紙画像を生成する(重い処理なので呼び出し回数を絞ること)。
    @MainActor
    private func makeExportImage() -> UIImage? {
        // 粒がきれいに散った状態になる時刻を固定で選び、毎回同じ絵になるようにする
        let composition = WallpaperComposition(
            placeName: placeName,
            weather: weather,
            degrees: degrees,
            orb: orb,
            staticTime: 1000
        )
        let renderer = ImageRenderer(content: composition.frame(width: 1242, height: 1242 * wallpaperAspect))
        renderer.scale = 1
        return renderer.uiImage
    }

    private var shareImage: Image {
        if let exportImage {
            return Image(uiImage: exportImage)
        }
        return Image(systemName: "photo")
    }

    private func save() {
        saveState = .saving
        guard let uiImage = exportImage ?? makeExportImage() else {
            saveState = .failed
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
                    } completionHandler: { success, _ in
                        DispatchQueue.main.async {
                            saveState = success ? .saved : .failed
                        }
                    }
                default:
                    saveState = .denied
                }
            }
        }
    }
}

/// 壁紙の見た目そのもの。プレビュー表示と、実際に書き出す高解像度画像の両方で
/// 同じビューを使うことで見た目のズレをなくす。
private struct WallpaperComposition: View {
    let placeName: String
    let weather: WeatherBundle
    let degrees: (Double) -> String
    let orb: DailyOrb?
    /// 画像として書き出す場合に、雨粒などのパーティクルを静止画として
    /// 描くための固定時刻。プレビュー表示ではアニメーションさせたいので nil。
    var staticTime: TimeInterval?

    var body: some View {
        ZStack {
            SkyBackground(
                kind: weather.kind,
                isDay: weather.isDay,
                sunrise: weather.sunrise,
                sunset: weather.sunset,
                staticTime: staticTime
            )

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                if let orb {
                    // staticTime がある = ImageRenderer での書き出し。TimelineView は描かれないので静止描画にする
                    OrbView(orb: orb, size: 96, animated: staticTime == nil)
                        .padding(.bottom, 18)
                }

                Text(placeName)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 2)

                Text(degrees(weather.temperature))
                    .font(.system(size: 118, weight: .thin))
                    .kerning(-2)
                    .foregroundStyle(
                        LinearGradient(colors: [.white, .white.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)

                Text(weather.kind.label)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 4)

                Spacer(minLength: 0)
                Spacer(minLength: 0)

                Text("そらだま")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 36)
            }
        }
    }
}
