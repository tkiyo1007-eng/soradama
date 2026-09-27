import Foundation
import Testing
@testable import AuroraWeather

@MainActor
struct CitySearchTests {
    private static let place = GeoPlace(id: 1, name: "テスト都市", latitude: 0, longitude: 0, country: nil, admin1: nil)

    @Test func newInputClearsOldResultsImmediately() async {
        let model = CitySearchModel(delay: 0) { _ in [Self.place] }
        await model.search("最初").value
        #expect(model.results.count == 1)
        let next = model.search("次の都市")
        #expect(model.results.isEmpty)
        #expect(model.isSearching)
        await next.value
        #expect(model.results.count == 1)
    }

    @Test func emptyInputDoesNotRequest() async {
        var calls = 0
        let model = CitySearchModel(delay: 0) { query in
            calls += 1
            #expect(query == "都市")
            return [Self.place]
        }
        await model.search("  都市\n").value
        await model.search(" \n ").value
        #expect(calls == 1)
        #expect(model.results.isEmpty)
        #expect(!model.isSearching && !model.hasFailed)
    }

    @Test func failureCanBeRetriedAndEmptySuccessIsNotFailure() async {
        var calls = 0
        let model = CitySearchModel(delay: 0) { _ in
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return []
        }
        await model.search("都市").value
        #expect(model.hasFailed && !model.isSearching)
        let retry = model.search("都市")
        #expect(!model.hasFailed && model.isSearching)
        await retry.value
        #expect(!model.hasFailed && !model.isSearching && model.results.isEmpty)
        #expect(calls == 2)
    }

    @Test func cancelledDebounceMakesNoRequest() async {
        var calls = 0
        let model = CitySearchModel { _ in calls += 1; return [] }
        let pending = model.search("都市")
        model.cancel()
        await pending.value
        #expect(calls == 0)
        #expect(!model.isSearching && !model.hasFailed)
    }

    @Test func lateResponseCannotOverwriteNewResults() async throws {
        var oldResponse: CheckedContinuation<[GeoPlace], Never>?
        let model = CitySearchModel(delay: 0) { query in
            if query == "古い" {
                return await withCheckedContinuation { oldResponse = $0 }
            }
            return []
        }
        let old = model.search("古い")
        // 待ち時間を固定せず、モックの開始を待つ。外部通信は行わない。
        while oldResponse == nil { await Task.yield() }
        await model.search("新しい").value
        oldResponse?.resume(returning: [Self.place])
        await old.value
        #expect(model.results.isEmpty)
        #expect(!model.isSearching && !model.hasFailed)
    }

    @Test func httpFailureIsNotAnEmptyResult() throws {
        let url = try #require(URL(string: "https://example.invalid/search"))
        for status in [400, 429, 500, 503] {
            let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
            #expect(throws: URLError.self) { try GeocodingService.decode(Data("{}".utf8), response: response) }
        }
        let ok = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        #expect(try GeocodingService.decode(Data("{}".utf8), response: ok).isEmpty)
        #expect(throws: (any Error).self) { try GeocodingService.decode(Data("invalid".utf8), response: ok) }
    }
}
