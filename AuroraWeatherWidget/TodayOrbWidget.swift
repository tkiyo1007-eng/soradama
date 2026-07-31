import WidgetKit
import SwiftUI

// MARK: - 今日の空玉ウィジェット

/// ホーム画面に「今日の空玉」を置くウィジェット。
/// アプリの差別化の核である空玉を、一番人目に触れる場所に出す。
/// タップするとアプリの空玉コレクションが直接開く(soradama://collection)。
struct TodayOrbEntry: TimelineEntry {
    let date: Date
    let orb: DailyOrb?
    let streak: Int
    let monthCount: Int

    static let placeholder = TodayOrbEntry(
        date: .now,
        orb: DailyOrb(
            dateKey: DailyOrb.key(for: .now),
            kind: .clear,
            tempMax: 24,
            tempMin: 16,
            humidity: 50,
            precipProbability: nil,
            placeName: "東京"
        ),
        streak: 7,
        monthCount: 12
    )
}

struct TodayOrbProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayOrbEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TodayOrbEntry) -> Void) {
        completion(context.isPreview ? .placeholder : makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayOrbEntry>) -> Void) {
        // 空玉はアプリを開いた時に記録される。日付が変わったら「まだ玉がない」表示に
        // 切り替わるよう、次の0時過ぎに更新を予約する(それ以外はアプリ側の
        // reloadAllTimelines で更新される)
        let calendar = Calendar.current
        let nextMidnight = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 5),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600 * 6)
        completion(Timeline(entries: [makeEntry()], policy: .after(nextMidnight)))
    }

    private func makeEntry() -> TodayOrbEntry {
        let store = OrbStore.shared
        return TodayOrbEntry(
            date: Date(),
            orb: store.orb(for: Date()),
            streak: store.streak,
            monthCount: store.count(inMonthOf: Date())
        )
    }
}

struct TodayOrbWidget: Widget {
    let kind = "TodayOrbWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayOrbProvider()) { entry in
            TodayOrbWidgetView(entry: entry)
        }
        .configurationDisplayName("今日の空玉")
        .description("今日の空が閉じ込められたガラス玉と連続日数を飾れます。")
        .supportedFamilies([.systemSmall])
    }
}

struct TodayOrbWidgetView: View {
    let entry: TodayOrbEntry

    var body: some View {
        VStack(spacing: 6) {
            if let orb = entry.orb {
                OrbView(orb: orb, size: 74, animated: false)
                Text(orb.kind.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                if entry.streak > 1 {
                    Text("\(entry.streak)日連続")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
            } else {
                // 今日まだアプリを開いていない日は、玉の獲得を促す
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .frame(width: 74, height: 74)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                Text("今日の空玉が\nまだありません")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.09, blue: 0.22), Color(red: 0.16, green: 0.15, blue: 0.36)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .widgetURL(URL(string: "soradama://collection"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            entry.orb.map { "今日の空玉、\($0.kind.label)、\(entry.streak)日連続" }
                ?? "今日の空玉はまだありません。アプリを開くと記録されます"
        )
    }
}
