import Foundation
import CoreLocation

enum LocationError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied:      return String(localized: "位置情報へのアクセスが許可されていません。")
        case .unavailable: return String(localized: "現在地を取得できませんでした。")
        }
    }
}

/// CLLocationManager を async/await でワンショット利用するラッパー。
///
/// `continuation` はデリゲート(CoreLocation のスレッド)とタイムアウト用の Task の
/// 両方から触られるため、クラスごとメインアクターに閉じて競合を防いでいる。
/// デリゲートメソッドは nonisolated で受けて、中でメインアクターへ渡し直す。
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation() async throws -> CLLocation {
        // 権限ダイアログに答えないままバックグラウンドへ行くなどで
        // デリゲートが呼ばれないと continuation が永久に宙吊りになり、
        // 以降のすべての現在地取得が失敗し続ける。20秒で必ず打ち切る。
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.resume(with: .failure(LocationError.unavailable))
        }
        defer { timeout.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            guard self.continuation == nil else {
                continuation.resume(throwing: LocationError.unavailable)
                return
            }
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                resume(with: .failure(LocationError.denied))
            default:
                manager.requestLocation()
            }
        }
    }

    private func resume(with result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    // MARK: CLLocationManagerDelegate
    //
    // CoreLocation はメインスレッドで呼ぶとは限らないため nonisolated で受け、
    // 状態に触る処理はメインアクターへ移す。

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self, self.continuation != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.resume(with: .failure(LocationError.denied))
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.first
        Task { @MainActor [weak self] in
            if let location {
                self?.resume(with: .success(location))
            } else {
                self?.resume(with: .failure(LocationError.unavailable))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.resume(with: .failure(LocationError.unavailable))
        }
    }
}
