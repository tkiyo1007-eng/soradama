import WidgetKit
import SwiftUI

// MARK: - タイムライン

struct WatchWeatherEntry: TimelineEntry {
    let date: Date
    let placeName: String
    let weather: WeatherBundle?

    static let placeholder = WatchWeatherEntry(date: .now, placeName: "東京", weather: nil)
}

struct WatchWeatherProvider: TimelineProvider {
    private let service = WeatherService()

    func placeholder(in context: Context) -> WatchWeatherEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WatchWeatherEntry) -> Void) {
        Task { completion(await makeEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchWeatherEntry>) -> Void) {
        Task {
            let entry = await makeEntry()
            // 文字盤は頻繁に見られるので30分ごとに更新する
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
                ?? Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func makeEntry() async -> WatchWeatherEntry {
        let place = SharedStore.lastPlace()
        let weather = try? await service.fetch(latitude: place.latitude, longitude: place.longitude)
        return WatchWeatherEntry(date: Date(), placeName: place.name, weather: weather)
    }
}

// MARK: - 気温の表示(iPhone 側の単位設定に追従する)

private func degrees(_ celsius: Double?) -> String {
    guard let celsius else { return "--°" }
    return "\(Int(SharedStore.units().convert(celsius).rounded()))°"
}

// MARK: - 円形(文字盤の丸い枠)

struct SoradamaCircularComplication: Widget {
    let kind = "SoradamaCircularComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchWeatherProvider()) { entry in
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    if let weather = entry.weather {
                        WeatherIconView(kind: weather.kind, isDay: weather.isDay)
                            .frame(width: 14, height: 14)
                    } else {
                        // 取得失敗時に晴れアイコンを捏造しない
                        Image(systemName: "questionmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(degrees(entry.weather?.temperature))
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
            .containerBackground(.clear, for: .widget)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.weather.map { "\($0.kind.label)、\(degrees($0.temperature))" } ?? "天気を取得できません")
        }
        .configurationDisplayName("天気")
        .description("現在の天気と気温を表示します。")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - 長方形(文字盤の横長の枠)

struct SoradamaRectangularComplication: Widget {
    let kind = "SoradamaRectangularComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchWeatherProvider()) { entry in
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if let weather = entry.weather {
                        WeatherIconView(kind: weather.kind, isDay: weather.isDay)
                            .frame(width: 13, height: 13)
                    }
                    Text(entry.placeName)
                        .font(.caption2)
                        .lineLimit(1)
                }
                Text(degrees(entry.weather?.temperature))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                if let weather = entry.weather {
                    Text("最高\(degrees(weather.todayMax)) 最低\(degrees(weather.todayMin))")
                        .font(.system(size: 11))
                        .opacity(0.75)
                        .lineLimit(1)
                } else {
                    Text("取得できません")
                        .font(.system(size: 11))
                        .opacity(0.75)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.clear, for: .widget)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.weather.map { "\(entry.placeName)、\($0.kind.label)、\(degrees($0.temperature))" } ?? "\(entry.placeName)、天気を取得できません")
        }
        .configurationDisplayName("天気(詳細)")
        .description("地点名・気温・最高最低を表示します。")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - インライン(文字盤の1行テキスト)

struct SoradamaInlineComplication: Widget {
    let kind = "SoradamaInlineComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchWeatherProvider()) { entry in
            Text(inlineText(entry))
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("天気(1行)")
        .description("気温と天気を1行で表示します。")
        .supportedFamilies([.accessoryInline])
    }

    private func inlineText(_ entry: WatchWeatherEntry) -> String {
        guard let weather = entry.weather else { return "そらだま --°" }
        return "\(degrees(weather.temperature)) \(weather.kind.label)"
    }
}

// MARK: - バンドル

@main
struct SoradamaWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        SoradamaCircularComplication()
        SoradamaRectangularComplication()
        SoradamaInlineComplication()
    }
}
