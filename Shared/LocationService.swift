import Foundation
import CoreLocation

enum LocationError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied:      return "位置情報へのアクセスが許可されていません。"
        case .unavailable: return "現在地を取得できませんでした。"
        }
    }
}

/// CLLocationManager を async/await でワンショット利用するラッパー
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
            await MainActor.run { self?.resume(with: .failure(LocationError.unavailable)) }
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

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            resume(with: .failure(LocationError.denied))
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            resume(with: .success(location))
        } else {
            resume(with: .failure(LocationError.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resume(with: .failure(LocationError.unavailable))
    }
}
