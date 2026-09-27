import Foundation

/// 地点の解決と保存を分け、画面を閉じた後の遅い応答でホームを変えない。
/// commitはMainActor上で同期的に行う。保存・通信方式自体は呼出元で維持する。
@MainActor
enum LocationSelectionOperation {
    static func perform(
        resolve: () async throws -> SavedPlace,
        commit: (SavedPlace) -> Void,
        reportError: (Error) -> Void
    ) async -> Bool {
        do {
            try Task.checkCancellation()
            let place = try await resolve()
            // CLLocation/Geocoderなど、取消後も返答する処理の結果も保存しない。
            // この確認とcommitの間にはawaitを挟まない。
            try Task.checkCancellation()
            commit(place)
            return true
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return false }
            reportError(error)
            return false
        }
    }
}
