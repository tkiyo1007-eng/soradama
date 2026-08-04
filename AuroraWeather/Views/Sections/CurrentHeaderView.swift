import SwiftUI

/// 画面上部の現在気温ヘッダー。スクロール量に応じて縮小・フェードする。
struct CurrentHeaderView: View {
    /// 気温の巨大表示。文字サイズ設定に追従しつつ、極端に大きくならないよう上限を設ける
    @ScaledMetric(relativeTo: .largeTitle) private var bigTempSize: CGFloat = 108
    let placeName: String
    let isCurrentLocation: Bool
    let weather: WeatherBundle
    let degrees: (Double) -> String
    let collapseProgress: Double // 0 = 展開, 1 = 折りたたみ

    /// 開いた瞬間に気温が立ち上がる演出。
    /// 0 から実際の気温へカウントアップさせることで、
    /// 数字が並ぶだけの画面に「作り込まれている」印象を与える。
    ///
    /// 表示は Int に丸めた文字列なので、`withAnimation` で Double の State を
    /// 変えるだけでは中間値が描画されない(かつ numericText が桁変化で破綻する)。
    /// そのため経過時間から進捗を計算し、TimelineView で毎フレーム描き直す。
    @State private var countUpStart: Date?
    @State private var hasAppeared = false

    private static let countUpDuration: TimeInterval = 0.9

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                if isCurrentLocation {
                    Image(systemName: "location.fill")
                        .font(.subheadline)
                }
                Text(placeName)
                    .font(.title2.weight(.medium))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)

            ZStack {
                // 展開時: 大きな気温
                VStack(spacing: 2) {
                    temperatureText
                        .font(.system(size: min(bigTempSize, 150), weight: .thin))
                        .kerning(-2)
                        // 巨大なフォントなので、レイアウト都合で「2...」のように
                        // 省略されないよう明示的に1行・縮小許可にする
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.75)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.20), radius: 12, y: 6)
                        .scaleEffect(hasAppeared ? 1.0 : 0.88)
                        .opacity(hasAppeared ? 1 : 0)

                    HStack(spacing: 8) {
                        WeatherIconView(kind: weather.kind, isDay: weather.isDay)
                            .frame(width: 26, height: 26)
                        Text(weather.kind.label)
                    }
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))

                    HStack(spacing: 14) {
                        Text("最高 \(degrees(weather.todayMax))")
                        Text("最低 \(degrees(weather.todayMin))")
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 2)

                    Text(OrbVoice.line(for: weather))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.top, 6)
                }
                .opacity(1 - collapseProgress * 1.6)
                .scaleEffect(1 - collapseProgress * 0.28, anchor: .top)

                // 折りたたみ時: コンパクト表示
                HStack(spacing: 8) {
                    Text(degrees(weather.temperature))
                    Text("|")
                        .foregroundStyle(.white.opacity(0.5))
                    Text(weather.kind.label)
                }
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.95))
                .opacity((collapseProgress - 0.6) * 2.5)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(placeName)、\(weather.kind.label)、現在\(degrees(weather.temperature))、最高\(degrees(weather.todayMax))、最低\(degrees(weather.todayMin))")
        .onAppear { animateIn() }
    }

    /// カウントアップ中は TimelineView で毎フレーム描き直し、
    /// 終わったら通常の Text に戻す(常時再描画を続けない)。
    @ViewBuilder
    private var temperatureText: some View {
        if let start = countUpStart {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSince(start)
                let progress = (elapsed / Self.countUpDuration).clamped(to: 0...1)
                // 終盤ほどゆっくり止まる(ease-out)
                let eased = 1 - pow(1 - progress, 3)
                Text(degrees(weather.temperature * eased))
                    .onChange(of: progress) { _, newValue in
                        if newValue >= 1 { countUpStart = nil }
                    }
            }
        } else {
            Text(degrees(weather.temperature))
                .contentTransition(.numericText())
        }
    }

    /// 開いた瞬間の演出。動きを減らす設定のときは即座に最終状態にする。
    private func animateIn() {
        guard !hasAppeared else { return }
        guard !reduceMotion else {
            hasAppeared = true
            return
        }
        countUpStart = Date()
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            hasAppeared = true
        }
    }
}
