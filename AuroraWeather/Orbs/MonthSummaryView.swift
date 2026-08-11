import SwiftUI

/// ひと月の空を1枚にまとめた振り返り画面。
/// そのまま SNS に貼れるカードとして書き出せる。
struct MonthSummaryView: View {
    let summary: MonthSummary
    let orbs: [DailyOrb]

    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: Image?

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        // 書式ごとロケールに委ねる(日本語 "2026年8月" / 英語 "August 2026")
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter
    }()

    private static func degrees(_ celsius: Double) -> String {
        "\(Int(SharedStore.units().convert(celsius).rounded()))°"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.07, green: 0.09, blue: 0.22), Color(red: 0.16, green: 0.15, blue: 0.36)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        card
                        Text("この画像を共有すると、ひと月の空をそのまま人に見せられます")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("今月の振り返り")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let shareImage {
                        ShareLink(
                            item: shareImage,
                            preview: SharePreview(String(localized: "\(Self.monthFormatter.string(from: summary.month))の空"), image: shareImage)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.white)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .task {
                // ImageRenderer は重いので表示後に一度だけ生成する
                let renderer = ImageRenderer(content: card)
                renderer.scale = 3
                if let uiImage = renderer.uiImage {
                    shareImage = Image(uiImage: uiImage)
                }
            }
        }
    }

    /// 共有カード本体(画面表示と書き出しで同じものを使う)
    private var card: some View {
        VStack(spacing: 16) {
            VStack(spacing: 3) {
                // 連結だと翻訳されない。補間を含む1つのキーとして訳せるようにする
                Text(String(localized: "\(Self.monthFormatter.string(from: summary.month))の空"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(summary.headline)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }

            // その月に集めた玉を並べる
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 7), count: 7), spacing: 9) {
                ForEach(orbs) { orb in
                    OrbView(orb: orb, size: 30, animated: false)
                }
            }

            HStack(spacing: 10) {
                stat(value: "\(summary.orbCount)", label: "集めた空")
                stat(value: "\(summary.sunnyDays)", label: "晴れた日")
                stat(value: "\(summary.rainyDays)", label: "雨の日")
                if summary.milestoneCount > 0 {
                    stat(value: "\(summary.milestoneCount)", label: "特別な玉")
                }
            }

            VStack(spacing: 6) {
                if let hottest = orbs.max(by: { $0.tempMax < $1.tempMax }), let date = hottest.date {
                    highlight(
                        icon: "thermometer.sun",
                        text: String(localized: "いちばん暑かったのは \(date.formatted(.dateTime.locale(Locale.current).month().day()))の \(Self.degrees(hottest.tempMax))")
                    )
                }
                if let coldest = orbs.min(by: { $0.tempMin < $1.tempMin }), let date = coldest.date {
                    highlight(
                        icon: "thermometer.snowflake",
                        text: String(localized: "いちばん寒かったのは \(date.formatted(.dateTime.locale(Locale.current).month().day()))の \(Self.degrees(coldest.tempMin))")
                    )
                }
            }

            VStack(spacing: 2) {
                Text("空玉 — 空を集める天気アプリ")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                Text("apps.apple.com/app/id6788443049")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.11, blue: 0.26), Color(red: 0.19, green: 0.18, blue: 0.42)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private func stat(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func highlight(icon: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
        }
    }
}
