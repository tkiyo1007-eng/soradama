import CoreLocation
import Foundation
import Testing
@testable import AuroraWeather

/// 実測位・権限ダイアログを使わず、取消後の再試行と旧要求の遅延イベントを検証する。
@MainActor
struct LocationServiceTests {
    private static var tokyo: CLLocation { CLLocation(latitude: 35.68, longitude: 139.76) }
    private static var paris: CLLocation { CLLocation(latitude: 48.85, longitude: 2.35) }

    @Test("通常の位置取得は一度だけ開始し、成功後の重複応答を無視する")
    func successAndDuplicateEvents() async throws {
        let fixture = Fixture()
        defer { fixture.finish() }
        let task = fixture.start()
        let client = fixture.clients[0]
        await client.waitForLocationRequest()
        let callback = try #require(client.onEvent)
        callback(.location(Self.tokyo))
        let location = try await task.value.get()
        callback(.failure)
        callback(.location(Self.paris))
        #expect(location.coordinate.latitude == Self.tokyo.coordinate.latitude)
        #expect(client.locationRequests == 1)
        #expect(client.authorizationRequests == 0)
    }

    @Test("拒否・制限時は認可や測位を追加要求しない", arguments: [CLAuthorizationStatus.denied, .restricted])
    func deniedAndRestricted(status: CLAuthorizationStatus) async {
        let fixture = Fixture(statuses: [status])
        defer { fixture.finish() }
        #expect(Self.isFailure(await fixture.start().value, matching: .denied))
        #expect(fixture.clients[0].authorizationRequests == 0)
        #expect(fixture.clients[0].locationRequests == 0)
    }

    @Test("認可待ちはWhenInUseを一度要求し、許可されてから測位する")
    func waitsForPermission() async throws {
        let fixture = Fixture(statuses: [.notDetermined])
        defer { fixture.finish() }
        let task = fixture.start()
        let client = fixture.clients[0]
        await client.waitForAuthorizationRequest()
        #expect(client.authorizationRequests == 1)
        #expect(client.locationRequests == 0)
        client.emit(.authorizationChanged(.authorizedWhenInUse))
        await client.waitForLocationRequest()
        client.emit(.location(Self.tokyo))
        _ = try await task.value.get()
        #expect(client.locationRequests == 1)
    }

    @Test("同じ認可状態が重複通知されても測位は一回")
    func duplicateAuthorizationDoesNotRestart() async throws {
        let fixture = Fixture()
        defer { fixture.finish() }
        let task = fixture.start()
        let client = fixture.clients[0]
        await client.waitForLocationRequest()
        client.emit(.authorizationChanged(.authorizedWhenInUse))
        client.emit(.authorizationChanged(.authorizedAlways))
        client.emit(.location(Self.tokyo))
        _ = try await task.value.get()
        #expect(client.locationRequests == 1)
        #expect(client.authorizationRequests == 0)
    }

    @Test("取得中の重複要求は最初の要求を壊さず拒否する")
    func concurrentRequestIsRejected() async throws {
        let fixture = Fixture()
        defer { fixture.finish() }
        let first = fixture.start()
        await fixture.clients[0].waitForLocationRequest()
        #expect(Self.isFailure(await fixture.start().value, matching: .unavailable))
        #expect(fixture.factory.count == 1)
        fixture.clients[0].emit(.location(Self.tokyo))
        _ = try await first.value.get()
        #expect(fixture.clients[0].locationRequests == 1)
    }

    @Test("開始前取消ではクライアントも認可要求も作らない")
    func cancellationBeforeStart() async {
        let fixture = Fixture()
        defer { fixture.finish() }
        let task = fixture.start()
        task.cancel()
        #expect(Self.isCancellation(await task.value))
        #expect(fixture.factory.count == 0)
        #expect(fixture.clients[0].authorizationRequests == 0)
        #expect(fixture.clients[0].locationRequests == 0)
    }

    @Test("測位待ちを取り消すと20秒を待たずに次の要求を受け付ける")
    func cancellationAllowsImmediateRetry() async throws {
        let fixture = Fixture(statuses: [.authorizedWhenInUse, .authorizedWhenInUse])
        defer { fixture.finish() }
        let first = fixture.start()
        await fixture.clients[0].waitForLocationRequest()
        first.cancel()
        #expect(Self.isCancellation(await first.value))
        #expect(fixture.clients[0].cancellations == 1)

        let second = fixture.start()
        await fixture.clients[1].waitForLocationRequest()
        fixture.clients[1].emit(.location(Self.paris))
        let location = try await second.value.get()
        #expect(location.coordinate.latitude == Self.paris.coordinate.latitude)
        #expect(fixture.factory.count == 2)
    }

    @Test("認可待ちの取消後に許可通知が届いても測位を始めない")
    func cancellationWhileAwaitingPermission() async throws {
        let fixture = Fixture(statuses: [.notDetermined])
        defer { fixture.finish() }
        let task = fixture.start()
        let client = fixture.clients[0]
        await client.waitForAuthorizationRequest()
        let callback = try #require(client.onEvent)
        task.cancel()
        #expect(Self.isCancellation(await task.value))
        callback(.authorizationChanged(.authorizedWhenInUse))
        #expect(client.authorizationRequests == 1)
        #expect(client.locationRequests == 0)
        #expect(client.cancellations == 1)
    }

    @Test("取消ハンドラのActor復帰前でも次の明示要求を受け付ける")
    func cancellationAndSynchronousRetry() async throws {
        let fixture = Fixture(statuses: [.authorizedWhenInUse, .authorizedWhenInUse])
        defer { fixture.finish() }
        let first = fixture.start()
        await fixture.clients[0].waitForLocationRequest()
        let retryClient = fixture.clients[1]
        retryClient.onLocationRequest = { [weak retryClient] in
            retryClient?.emit(.location(Self.paris))
        }

        first.cancel()
        // 旧Taskや取消ハンドラを待たず、このActorからそのまま再要求する。
        let retryResult: Result<CLLocation, Error>
        do { retryResult = .success(try await fixture.service.currentLocation()) }
        catch { retryResult = .failure(error) }

        // 再要求の成否によらず、取り消した旧Taskを回収してからassertする。
        let firstResult = await first.value
        #expect(Self.isCancellation(firstResult))
        let location = try retryResult.get()
        #expect(location.coordinate.latitude == Self.paris.coordinate.latitude)
        #expect(fixture.factory.count == 2)
        #expect(retryClient.locationRequests == 1)
    }

    @Test("旧要求の成功・失敗・認可通知が新要求へ混入しない")
    func oldEventsCannotCompleteNewRequest() async throws {
        let fixture = Fixture(statuses: [.authorizedWhenInUse, .authorizedWhenInUse])
        defer { fixture.finish() }
        let first = fixture.start()
        await fixture.clients[0].waitForLocationRequest()
        let oldCallback = try #require(fixture.clients[0].onEvent)
        first.cancel()
        #expect(Self.isCancellation(await first.value))

        let second = fixture.start()
        await fixture.clients[1].waitForLocationRequest()
        oldCallback(.location(Self.tokyo))
        oldCallback(.failure)
        oldCallback(.authorizationChanged(.denied))
        oldCallback(.authorizationChanged(.authorizedWhenInUse))
        fixture.clients[1].emit(.location(Self.paris))
        let location = try await second.value.get()
        #expect(location.coordinate.latitude == Self.paris.coordinate.latitude)
        #expect(fixture.clients[1].locationRequests == 1)
    }

    @Test("取消を無視して満了した旧タイマーが新要求を終了しない")
    func oldTimeoutCannotCompleteNewRequest() async throws {
        let fixture = Fixture(statuses: [.authorizedWhenInUse, .authorizedWhenInUse])
        defer { fixture.finish() }
        let first = fixture.start()
        await fixture.clients[0].waitForLocationRequest()
        await fixture.deadline.waitUntilStarted(1)
        first.cancel()
        #expect(Self.isCancellation(await first.value))

        let second = fixture.start()
        await fixture.clients[1].waitForLocationRequest()
        fixture.deadline.release(0)
        await fixture.deadline.waitUntilReturned(0)
        // 秒数で待たず、再開したtimeout処理へexecutorを譲る。
        await Task.yield()
        fixture.clients[1].emit(.location(Self.paris))
        let location = try await second.value.get()
        #expect(location.coordinate.latitude == Self.paris.coordinate.latitude)
    }

    @Test("タイムアウトした要求を解放し、次の要求で取得できる")
    func timeoutAllowsRetry() async throws {
        let fixture = Fixture(statuses: [.authorizedWhenInUse, .authorizedWhenInUse])
        defer { fixture.finish() }
        let first = fixture.start()
        await fixture.clients[0].waitForLocationRequest()
        await fixture.deadline.waitUntilStarted(1)
        fixture.deadline.release(0)
        #expect(Self.isFailure(await first.value, matching: .unavailable))
        #expect(fixture.clients[0].cancellations == 1)

        let second = fixture.start()
        await fixture.clients[1].waitForLocationRequest()
        fixture.clients[1].emit(.location(Self.paris))
        _ = try await second.value.get()
    }

    @Test("空の位置応答と取得失敗を正常な位置へ置き換えない", arguments: [false, true])
    func emptyLocationAndFailure(failureEvent: Bool) async {
        let fixture = Fixture()
        defer { fixture.finish() }
        let task = fixture.start()
        await fixture.clients[0].waitForLocationRequest()
        fixture.clients[0].emit(failureEvent ? .failure : .location(nil))
        #expect(Self.isFailure(await task.value, matching: .unavailable))
        #expect(fixture.clients[0].locationRequests == 1)
    }

    private static func isCancellation(_ result: Result<CLLocation, Error>) -> Bool {
        guard case .failure(let error) = result else { return false }
        return error is CancellationError
    }

    private static func isFailure(_ result: Result<CLLocation, Error>, matching expected: LocationError) -> Bool {
        guard case .failure(let error) = result, let actual = error as? LocationError else { return false }
        switch (actual, expected) {
        case (.denied, .denied), (.unavailable, .unavailable): return true
        default: return false
        }
    }

    @MainActor
    private final class Fixture {
        let clients: [FakeClient]
        let factory: ClientFactory
        let deadline: ControlledDeadline
        let service: LocationService
        private var watchdog: Task<Void, Never>?
        private var watchdogFired = false

        init(statuses: [CLAuthorizationStatus] = [.authorizedWhenInUse]) {
            clients = statuses.map(FakeClient.init)
            factory = ClientFactory(clients: clients)
            deadline = ControlledDeadline()
            service = LocationService(makeClient: factory.makeClient, waitForTimeout: deadline.wait)
            watchdog = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self else { return }
                watchdogFired = true
                for client in clients {
                    client.emit(.failure)
                    client.releaseWaiters()
                }
                deadline.releaseAll()
            }
        }

        func start() -> Task<Result<CLLocation, Error>, Never> {
            Task { @MainActor in
                do { return .success(try await service.currentLocation()) }
                catch { return .failure(error) }
            }
        }

        func finish() {
            watchdog?.cancel()
            #expect(!watchdogFired, "要求が完了せず、2秒のfailure watchdogで解放した")
            deadline.releaseAll()
            for client in clients { client.releaseWaiters() }
        }
    }

    @MainActor
    private final class ClientFactory {
        let clients: [FakeClient]
        private(set) var count = 0

        init(clients: [FakeClient]) { self.clients = clients }

        func makeClient() -> any LocationRequestClient {
            let index = count
            count += 1
            #expect(index < clients.count, "想定していない追加の位置取得クライアントを作成した")
            return clients[min(index, clients.count - 1)]
        }
    }

    @MainActor
    private final class FakeClient: LocationRequestClient {
        var authorizationStatus: CLAuthorizationStatus
        var onEvent: ((LocationRequestEvent) -> Void)?
        var onLocationRequest: (() -> Void)?
        private(set) var authorizationRequests = 0
        private(set) var locationRequests = 0
        private(set) var cancellations = 0
        private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
        private var locationWaiters: [CheckedContinuation<Void, Never>] = []

        init(status: CLAuthorizationStatus) { authorizationStatus = status }

        func requestWhenInUseAuthorization() {
            authorizationRequests += 1
            let waiters = authorizationWaiters
            authorizationWaiters = []
            waiters.forEach { $0.resume() }
        }

        func requestLocation() {
            locationRequests += 1
            let waiters = locationWaiters
            locationWaiters = []
            waiters.forEach { $0.resume() }
            onLocationRequest?()
        }

        func cancel() { cancellations += 1 }

        func emit(_ event: LocationRequestEvent) {
            if case .authorizationChanged(let status) = event { authorizationStatus = status }
            onEvent?(event)
        }

        func waitForAuthorizationRequest() async {
            guard authorizationRequests == 0 else { return }
            await withCheckedContinuation { authorizationWaiters.append($0) }
        }

        func waitForLocationRequest() async {
            guard locationRequests == 0 else { return }
            await withCheckedContinuation { locationWaiters.append($0) }
        }

        func releaseWaiters() {
            let waiters = authorizationWaiters + locationWaiters
            authorizationWaiters = []
            locationWaiters = []
            waiters.forEach { $0.resume() }
        }
    }

    /// 取消を自動反映しないタイマーで、取消後に届くtimeoutも再現する。
    @MainActor
    private final class ControlledDeadline {
        private var pending: [CheckedContinuation<Void, Error>?] = []
        private var returned: Set<Int> = []
        private var starts: [(Int, CheckedContinuation<Void, Never>)] = []
        private var returns: [(Int, CheckedContinuation<Void, Never>)] = []
        private var isFinished = false

        func wait() async throws {
            guard !isFinished else { return }
            let index = pending.count
            try await withCheckedThrowingContinuation { continuation in
                pending.append(continuation)
                let ready = starts.filter { $0.0 <= pending.count }
                starts.removeAll { $0.0 <= pending.count }
                ready.forEach { $0.1.resume() }
            }
            returned.insert(index)
            let ready = returns.filter { $0.0 == index }
            returns.removeAll { $0.0 == index }
            ready.forEach { $0.1.resume() }
        }

        func waitUntilStarted(_ count: Int) async {
            guard pending.count < count, !isFinished else { return }
            await withCheckedContinuation { starts.append((count, $0)) }
        }

        func waitUntilReturned(_ index: Int) async {
            guard !returned.contains(index), !isFinished else { return }
            await withCheckedContinuation { returns.append((index, $0)) }
        }

        func release(_ index: Int) {
            guard pending.indices.contains(index) else { return }
            let continuation = pending[index]
            pending[index] = nil
            continuation?.resume()
        }

        func releaseAll() {
            isFinished = true
            for index in pending.indices { release(index) }
            let waiters = starts + returns
            starts = []
            returns = []
            waiters.forEach { $0.1.resume() }
        }
    }
}
