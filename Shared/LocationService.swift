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

enum LocationRequestEvent {
    case authorizationChanged(CLAuthorizationStatus)
    case location(CLLocation?)
    case failure
}

/// 一度の測位要求にだけ使う。テストでは実際に測位しないclientへ差し替える。
@MainActor
protocol LocationRequestClient: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var onEvent: ((LocationRequestEvent) -> Void)? { get set }
    func requestWhenInUseAuthorization()
    func requestLocation()
    func cancel()
}

/// onCancelは任意のexecutorから来るため、この1ビットだけをlockで保護する。
/// MainActorへ取消処理が届く前の即時再試行でも、古い要求を解放できる。
private final class LocationRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }
}

/// 取消・タイムアウト・delegate応答を要求IDで照合し、必ず一度だけ完了する。
@MainActor
final class LocationService {
    private struct Request {
        let id: UUID
        let cancellation: LocationRequestCancellation
        let client: any LocationRequestClient
        let continuation: CheckedContinuation<CLLocation, Error>
        let timeout: Task<Void, Never>
        var didRequestLocation = false
    }

    private var request: Request?
    private let makeClient: @MainActor () -> any LocationRequestClient
    private let waitForTimeout: @MainActor () async throws -> Void

    init(
        makeClient: @escaping @MainActor () -> any LocationRequestClient = { CoreLocationRequestClient() },
        waitForTimeout: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .seconds(20)) }
    ) {
        self.makeClient = makeClient
        self.waitForTimeout = waitForTimeout
    }

    func currentLocation() async throws -> CLLocation {
        try Task.checkCancellation()
        if let current = request, current.cancellation.isCancelled {
            finish(current.id, with: .failure(CancellationError()))
        }
        guard request == nil else { throw LocationError.unavailable }
        let id = UUID()
        let cancellation = LocationRequestCancellation()
        let location: CLLocation = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
                // onCancelは別スレッドから来る可能性がある。登録前の取消も取りこぼさない。
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let client = makeClient()
                client.onEvent = { [weak self] event in self?.receive(event, for: id) }
                // 従来どおり20秒で打ち切る。取消済みの古いdeadlineは新要求に触れない。
                let timeout = Task<Void, Never> { [weak self, waitForTimeout] in
                    do { try await waitForTimeout() } catch { return }
                    guard !Task.isCancelled else { return }
                    self?.finish(id, with: .failure(LocationError.unavailable))
                }
                request = Request(id: id, cancellation: cancellation, client: client,
                                  continuation: continuation, timeout: timeout)
                switch client.authorizationStatus {
                case .notDetermined:
                    client.requestWhenInUseAuthorization()
                case .denied, .restricted:
                    finish(id, with: .failure(LocationError.denied))
                default:
                    requestLocation(for: id)
                }
            }
        } onCancel: {
            cancellation.cancel()
            Task { @MainActor [weak self] in
                self?.finish(id, with: .failure(CancellationError()))
            }
        }
        try Task.checkCancellation()
        return location
    }

    private func receive(_ event: LocationRequestEvent, for id: UUID) {
        guard let current = request, current.id == id else { return }
        guard !current.cancellation.isCancelled else {
            finish(id, with: .failure(CancellationError()))
            return
        }
        switch event {
        case .authorizationChanged(let status):
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                requestLocation(for: id)
            case .denied, .restricted:
                finish(id, with: .failure(LocationError.denied))
            default:
                break
            }
        case .location(let location):
            if let location { finish(id, with: .success(location)) }
            else { finish(id, with: .failure(LocationError.unavailable)) }
        case .failure:
            finish(id, with: .failure(LocationError.unavailable))
        }
    }

    private func requestLocation(for id: UUID) {
        guard let current = request, current.id == id, !current.didRequestLocation else { return }
        guard !current.cancellation.isCancelled else {
            finish(id, with: .failure(CancellationError()))
            return
        }
        // manager生成時の認可通知と、すでに許可済みの明示開始が重なっても1回だけ。
        request?.didRequestLocation = true
        current.client.requestLocation()
    }

    private func finish(_ id: UUID, with result: Result<CLLocation, Error>) {
        guard let current = request, current.id == id else { return }
        request = nil
        current.timeout.cancel()
        current.client.onEvent = nil
        current.client.cancel()
        let completion: Result<CLLocation, Error> = current.cancellation.isCancelled
            ? .failure(CancellationError()) : result
        current.continuation.resume(with: completion)
    }
}

/// CLLocationManager自体も要求ごとに分け、旧delegateが次の要求へ届かないようにする。
@MainActor
private final class CoreLocationRequestClient: NSObject, LocationRequestClient, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var isCancelled = false
    var onEvent: ((LocationRequestEvent) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }
    func requestWhenInUseAuthorization() { manager.requestWhenInUseAuthorization() }
    func requestLocation() { manager.requestLocation() }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onEvent = nil
        manager.delegate = nil
        // SDKのrequestLocation仕様: 単発の測位要求もこれで明示的に取消できる。
        manager.stopUpdatingLocation()
    }

    // CoreLocationのcallbackはMainActorへ渡し直す。取消後にqueueへ残った通知も無視する。
    private func emit(_ event: LocationRequestEvent) {
        guard !isCancelled else { return }
        onEvent?(event)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.emit(.authorizationChanged(status))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.first
        Task { @MainActor [weak self] in
            self?.emit(.location(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.emit(.failure)
        }
    }
}
