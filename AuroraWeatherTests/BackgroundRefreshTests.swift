import Testing
@testable import AuroraWeather

/// BGTask の期限切れと非同期処理の完了が競合しても、iOS へ返す結果を一意にする。
struct BackgroundRefreshTests {

    @Test("更新成功かつ未キャンセルなら成功になる")
    func successfulRefreshCompletesSuccessfully() {
        #expect(BackgroundRefreshCompletion.success(
            refreshSucceeded: true,
            isCancelled: false
        ))
    }

    @Test("期限切れでキャンセルされた処理は失敗になる")
    func cancelledRefreshCompletesWithFailure() {
        #expect(!BackgroundRefreshCompletion.success(
            refreshSucceeded: true,
            isCancelled: true
        ))
    }

    @Test("更新自体が失敗した処理も失敗になる")
    func failedRefreshCompletesWithFailure() {
        #expect(!BackgroundRefreshCompletion.success(
            refreshSucceeded: false,
            isCancelled: false
        ))
    }
}
