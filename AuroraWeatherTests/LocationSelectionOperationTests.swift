import Foundation
import Testing
@testable import AuroraWeather

/// 実際の測位・保存・天気APIを使わず、キャンセルを無視する遅延応答も再現する。
@MainActor
struct LocationSelectionOperationTests {
    private static let original = SavedPlace(name: "Tokyo", detail: "Japan", latitude: 35.68, longitude: 139.76)
    private static let selected = SavedPlace(name: "Paris", detail: "France", latitude: 48.85, longitude: 2.35)

    @Test("取得成功時だけ地点を一度確定する")
    func successCommitsOnce() async {
        let state = SelectionState()
        let result = await LocationSelectionOperation.perform(
            resolve: { Self.selected }, commit: state.commit, reportError: state.reportError
        )
        #expect(result)
        #expect(state.place == Self.selected)
        #expect(state.commitCount == 1)
        #expect(state.errorCount == 0)
    }

    @Test("取得失敗は元のホームを保持してエラーを通知する")
    func failurePreservesSelection() async {
        let state = SelectionState()
        let result = await LocationSelectionOperation.perform(
            resolve: { throw LocationError.unavailable }, commit: state.commit, reportError: state.reportError
        )
        #expect(!result)
        #expect(state.place == Self.original)
        #expect(state.commitCount == 0)
        #expect(state.errorCount == 1)
    }

    @Test("取得側が返した取消も通信エラーとして表示しない")
    func providerCancellationDoesNotReportError() async {
        let state = SelectionState()
        let result = await LocationSelectionOperation.perform(
            resolve: { throw CancellationError() }, commit: state.commit, reportError: state.reportError
        )
        #expect(!result)
        #expect(state.place == Self.original)
        #expect(state.commitCount == 0)
        #expect(state.errorCount == 0)
    }

    @Test("開始前に取り消した要求は測位も保存も開始しない")
    func cancelledBeforeStartDoesNotResolve() async {
        let state = SelectionState()
        var resolveCount = 0
        let task = Task { @MainActor in
            await LocationSelectionOperation.perform(resolve: {
                resolveCount += 1
                return Self.selected
            }, commit: state.commit, reportError: state.reportError)
        }
        task.cancel()
        let result = await task.value
        #expect(!result)
        #expect(resolveCount == 0)
        #expect(state.commitCount == 0)
        #expect(state.errorCount == 0)
    }

    @Test("画面を閉じた後の成功応答はホームを変更しない")
    func cancelledLateSuccessDoesNotCommit() async {
        let state = SelectionState()
        let request = PendingLocation()
        let task = Task { @MainActor in
            await LocationSelectionOperation.perform(
                resolve: request.resolve, commit: state.commit, reportError: state.reportError
            )
        }
        await request.waitUntilStarted()
        task.cancel()
        request.finish(.success(Self.selected))
        let result = await task.value
        #expect(!result)
        #expect(state.place == Self.original)
        #expect(state.commitCount == 0)
        #expect(state.errorCount == 0)
    }

    @Test("取消後の失敗応答は次の画面へエラーを残さない")
    func cancelledLateFailureDoesNotReportError() async {
        let state = SelectionState()
        let request = PendingLocation()
        let task = Task { @MainActor in
            await LocationSelectionOperation.perform(
                resolve: request.resolve, commit: state.commit, reportError: state.reportError
            )
        }
        await request.waitUntilStarted()
        task.cancel()
        request.finish(.failure(LocationError.unavailable))
        let result = await task.value
        #expect(!result)
        #expect(state.place == Self.original)
        #expect(state.commitCount == 0)
        #expect(state.errorCount == 0)
    }

    @Test("再選択した地点を取消済みの旧要求で上書きしない")
    func oldResponseDoesNotOverwriteNewSelection() async {
        let state = SelectionState()
        let oldRequest = PendingLocation()
        let oldTask = Task { @MainActor in
            await LocationSelectionOperation.perform(
                resolve: oldRequest.resolve, commit: state.commit, reportError: state.reportError
            )
        }
        await oldRequest.waitUntilStarted()
        oldTask.cancel()
        let newResult = await LocationSelectionOperation.perform(
            resolve: { Self.selected }, commit: state.commit, reportError: state.reportError
        )
        oldRequest.finish(.success(Self.original))
        let oldResult = await oldTask.value
        #expect(newResult)
        #expect(!oldResult)
        #expect(state.place == Self.selected)
        #expect(state.commitCount == 1)
        #expect(state.errorCount == 0)
    }

    @MainActor
    private final class SelectionState {
        var place = LocationSelectionOperationTests.original
        var commitCount = 0
        var errorCount = 0

        func commit(_ place: SavedPlace) {
            self.place = place
            commitCount += 1
        }

        func reportError(_ error: Error) { errorCount += 1 }
    }

    @MainActor
    private final class PendingLocation {
        private var response: CheckedContinuation<SavedPlace, Error>?
        private var started: CheckedContinuation<Void, Never>?

        func resolve() async throws -> SavedPlace {
            try await withCheckedThrowingContinuation { continuation in
                response = continuation
                started?.resume()
                started = nil
            }
        }

        func waitUntilStarted() async {
            if response != nil { return }
            await withCheckedContinuation { started = $0 }
        }

        func finish(_ result: Result<SavedPlace, Error>) {
            let continuation = response
            response = nil
            continuation?.resume(with: result)
        }
    }
}
