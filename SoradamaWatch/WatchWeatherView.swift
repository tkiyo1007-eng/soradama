import SwiftUI
import Observation
import CoreLocation
import WidgetKit

// MARK: - Watch 用ビューモデル

@Observable
@MainActor
final class WatchWeatherModel {
    var weather: WeatherBundle?
    var placeName: String = SharedStore.lastPlace().name
    var failed = false
    var isLoading = false
    var errorMessage: String?
    var cachedAt: Date?

    private let service = WeatherService()
    private let locationService = LocationService()
    /// 読み込み中に新しいiPhone設定が届いたら世代を進め、旧結果を適用せず再取得する。
    private var loadGeneration = 0

    func load() async {
        loadGeneration &+= 1
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        while true {
            let generation = loadGeneration
            await performLoad(generation: generation)
            if generation == loadGeneration { break }
        }
    }

    private func performLoad(generation: Int) async {
        failed = false
        errorMessage = nil
        cachedAt = nil

        // iPhone 側から WatchConnectivity で同期された地点を優先する。
        // 以前は現在地を無条件に優先していたため、iPhone で大阪を選んでいても
        // Watch だけ現在地を表示してしまい、2つの端末で違う天気が出ていた。
        var place = SharedStore.lastPlace()
        var expectedStoredPlace = place
        let shouldUseWatchLocation = !WatchSyncService.hasReceivedSettings || place.isCurrentLocation
        if shouldUseWatchLocation {
            do {
                let location = try await locationService.currentLocation()
                guard generation == loadGeneration,
                      SharedStore.lastPlace() == expectedStoredPlace else { return }
                // iPhoneから設定をまだ一度も受け取っていないWatchは東京へ固定せず現在地を使う。
                // 同期後は、iPhone側も「現在地」のときだけWatch自身の測位で更新する。
                place = SavedPlace(
                    name: String(localized: "現在地"),
                    detail: "",
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    isCurrentLocation: true
                )
                SharedStore.saveLastPlace(place)
                expectedStoredPlace = place
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                guard generation == loadGeneration,
                      SharedStore.lastPlace() == expectedStoredPlace else { return }
                if !WatchSyncService.hasReceivedSettings, !place.isCurrentLocation {
                    // 初回同期も過去のWatch現在地も無い状態では、東京を利用者の
                    // 現在地であるかのように表示せず、位置情報エラーを明示する。
                    weather = nil
                    errorMessage = error.soradamaMessage
                    failed = true
                    return
                }
            }
        }
        placeName = place.name

        do {
            let freshWeather = try await service.fetch(
                latitude: place.latitude,
                longitude: place.longitude
            )
            guard generation == loadGeneration,
                  SharedStore.lastPlace() == expectedStoredPlace else { return }
            weather = freshWeather
            WeatherSnapshotCache.save(freshWeather, for: place)
        } catch {
            guard generation == loadGeneration,
                  SharedStore.lastPlace() == expectedStoredPlace else { return }
            if let cached = WeatherSnapshotCache.loadSnapshot(for: place) {
                weather = cached.weather
                cachedAt = cached.savedAt
            } else {
                weather = nil
                // 有効なキャッシュもない場合は、圏外の理由を利用者に伝える。
                errorMessage = error.soradamaMessage
                failed = true
            }
        }
    }
}

// MARK: - メイン画面

struct WatchWeatherView: View {
    @State private var model = WatchWeatherModel()

    /// iPhone 側から WatchConnectivity で同期された単位で気温を表示する。
    private func degrees(_ celsius: Double) -> String {
        "\(Int(SharedStore.units().convert(celsius).rounded()))°"
    }

    var body: some View {
        Group {
            if let weather = model.weather {
                content(weather)
            } else if model.failed {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title2)
                    Text(model.errorMessage ?? String(localized: "取得に失敗しました"))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("再試行") {
                        Task { await model.load() }
                    }
                }
            } else {
                ProgressView("取得中…")
            }
        }
        .task { await model.load() }
        .onReceive(NotificationCenter.default.publisher(for: WatchSyncService.settingsDidChange)) { _ in
            Task { await model.load() }
        }
    }

    private func content(_ weather: WeatherBundle) -> some View {
        ZStack {
            LinearGradient(
                colors: weather.kind.skyColors(isDay: weather.isDay),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 10) {
                    header(weather)
                    if !weather.upcomingHours().isEmpty {
                        hourlyCard(weather)
                    }
                    if !weather.upcomingDays().isEmpty {
                        dailyCard(weather)
                    }

                    Button {
                        Task { await model.load() }
                    } label: {
                        Label("更新", systemImage: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.4))

                    VStack(spacing: 8) {
                        Link("天気データ: Open-Meteo", destination: DataAttribution.openMeteo)
                        Link("ライセンス: CC BY 4.0", destination: DataAttribution.creativeCommons)
                        Link("Open-Meteoの利用条件", destination: DataAttribution.openMeteoLicence)
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 4)
            }
        }
        .foregroundStyle(.white)
    }

    private func header(_ weather: WeatherBundle) -> some View {
        VStack(spacing: 1) {
            Text(model.placeName)
                .font(.footnote.weight(.medium))
                .opacity(0.85)
            if let cachedAt = model.cachedAt {
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("保存済みの天気")
                    Text(cachedAt, style: .relative)
                }
                .font(.caption2)
                .opacity(0.85)
            }
            Text(degrees(weather.temperature))
                .font(.system(size: 46, weight: .light))
            HStack(spacing: 5) {
                WeatherIconView(kind: weather.kind, isDay: weather.isDay)
                    .frame(width: 16, height: 16)
                Text(weather.kind.label)
            }
            .font(.footnote)
            Text("最高 \(degrees(weather.todayMax))  最低 \(degrees(weather.todayMin))")
                .font(.caption2)
                .opacity(0.85)
                .padding(.top, 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func hourlyCard(_ weather: WeatherBundle) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(weather.upcomingHours().dropFirst().prefix(6))) { hour in
                HStack {
                    Text(hour.date.hourLabel(in: weather.timeZone))
                        .font(.caption2)
                        .opacity(0.8)
                        .frame(width: 42, alignment: .leading)
                    WeatherIconView(kind: hour.kind, isDay: hour.isDay)
                        .frame(width: 14, height: 14)
                    Spacer()
                    if let probability = hour.precipitationProbability, probability >= 20 {
                        Text("\(Int(probability))%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 0.55, green: 0.85, blue: 1.0))
                    }
                    Text(degrees(hour.temperature))
                        .font(.caption.weight(.semibold))
                        .frame(width: 32, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(10)
        .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func dailyCard(_ weather: WeatherBundle) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(weather.upcomingDays().prefix(5))) { day in
                HStack {
                    Text(day.date.weekdayLabel(in: weather.timeZone))
                        .font(.caption2)
                        .opacity(0.8)
                        .frame(width: 26, alignment: .leading)
                    WeatherIconView(kind: day.kind, isDay: true)
                        .frame(width: 14, height: 14)
                    Spacer()
                    Text(degrees(day.tempMin))
                        .font(.caption2)
                        .opacity(0.65)
                    Text(degrees(day.tempMax))
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(10)
        .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    WatchWeatherView()
}
