import Foundation
import Testing
@testable import AuroraWeather

@MainActor
struct JapaneseCitySearchTests {
    private let japanese = Locale(identifier: "ja_JP")

    @Test func bundledIndexIsPresentAndUnambiguous() throws {
        struct Document: Decodable { let entries: [JapaneseCityIndex.Entry] }
        let url = try #require(Bundle.main.url(forResource: "JapaneseCityIndex", withExtension: "json"))
        let entries = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url)).entries
        #expect(entries.count >= 1800)
        #expect(Set(entries.map(\.prefecture)).count == 47)
        #expect(Set(entries.map(\.id)).count == entries.count)
        #expect(Set(entries.map { "\($0.prefecture)/\($0.name)" }).count == entries.count)
        #expect(entries.allSatisfy {
            $0.latitude.isFinite && $0.longitude.isFinite
                && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude)
                && !$0.name.isEmpty && !$0.nameEn.isEmpty && !$0.prefectureEn.isEmpty
        })
        #expect(!entries.contains { [1863291, 7418326, 7418329, 7506665, 7506666, 8739978].contains($0.id) })
        #expect(Bundle.main.url(forResource: "JapaneseCityIndex-LICENSE", withExtension: "txt") != nil)
    }

    @Test(arguments: ["上越", " 上越\n", "じょ", "ジョ", "ｼﾞｮ"])
    func shortJoetsuQueryNeedsNoNetwork(_ query: String) async throws {
        var requests = 0
        let service = GeocodingService(locale: japanese) { _ in
            requests += 1
            throw URLError(.notConnectedToInternet)
        }
        let results = try await service.search(query)
        let joetsu = try #require(results.first { $0.id == 6825489 })
        #expect(joetsu.name == "上越市")
        #expect(joetsu.admin1 == "新潟県")
        #expect(joetsu.latitude == 37.14828 && joetsu.longitude == 138.23642)
        #expect(requests == 0)
    }

    @Test(arguments: [("札", "札幌市"), ("横須", "横須賀市"), ("小布", "小布施町"),
                      ("白馬", "白馬村"), ("那", "那覇市"), ("上", "上越市")])
    func municipalitiesCanBeFoundFromTheirBeginning(_ sample: (String, String)) async throws {
        let service = GeocodingService(locale: japanese) { _ in
            Issue.record("Short indexed Japanese queries should not require the network")
            throw URLError(.notConnectedToInternet)
        }
        let results = try await service.search(sample.0)
        #expect(results.contains { $0.name == sample.1 })
        #expect(results.count <= 12)
        #expect(Set(results.map(\.id)).count == results.count)
    }

    @Test func indexUsesPrefixesRatherThanUnrelatedSubstrings() {
        let index = JapaneseCityIndex.bundled
        #expect(index.search("越", language: "ja", limit: 1000).allSatisfy { $0.id != 6825489 })
        #expect(index.search("  ", language: "ja").isEmpty)
        #expect(index.search("上越", language: "ja", limit: 0).isEmpty)
        #expect(index.search("上越", language: "ja").first?.name == "上越市")
    }

    @Test func localNamesFollowEnglishDisplayLanguage() async throws {
        let service = GeocodingService(locale: Locale(identifier: "en_US")) { _ in
            Issue.record("Indexed short query must be local in English too")
            throw URLError(.notConnectedToInternet)
        }
        let place = try #require(try await service.search("上越").first { $0.id == 6825489 })
        #expect(place.name != "上越市")
        #expect(place.country == "Japan")
        #expect(place.admin1 != "新潟県")
    }

    @Test(arguments: ["Paris", "London", "10001", "NY"])
    func globalSearchStillMakesOneUnmodifiedRequest(_ query: String) async throws {
        var requested: [URL] = []
        let service = GeocodingService(locale: Locale(identifier: "en_US")) { url in
            requested.append(url)
            return try Self.response(url: url, json: """
            {"results":[{"id":99,"name":"Fixture City","latitude":0,"longitude":0}]}
            """)
        }
        let results = try await service.search(query)
        #expect(results.map(\.id) == [99])
        #expect(requested.count == 1)
        let components = try #require(URLComponents(url: requested[0], resolvingAgainstBaseURL: false))
        #expect(components.host == "geocoding-api.open-meteo.com")
        #expect(components.queryItems?.first { $0.name == "name" }?.value == query)
        #expect(components.queryItems?.first { $0.name == "language" }?.value == "en")
        #expect(components.queryItems?.first { $0.name == "count" }?.value == "12")
    }

    @Test func completeNameDeduplicatesLocalAndRemoteAndKeepsSavedIdentity() async throws {
        var calls = 0
        let service = GeocodingService(locale: japanese) { url in
            calls += 1
            return try Self.response(url: url, json: """
            {"results":[{"id":6825489,"name":"上越市","latitude":37.14828,"longitude":138.23642,"country":"日本","admin1":"新潟県"}]}
            """)
        }
        let short = try #require(try await service.search("上越").first)
        let complete = try await service.search("上越市")
        #expect(calls == 1)
        #expect(complete.filter { $0.id == short.id }.count == 1)
        #expect(complete.first?.asSavedPlace.id == short.asSavedPlace.id)
        let encoded = try JSONEncoder().encode(short.asSavedPlace)
        let restored = try JSONDecoder().decode(SavedPlace.self, from: encoded)
        #expect(restored.id == short.asSavedPlace.id && restored.name == "上越市")
    }

    @Test func successfulEmptyRemoteCanUseLongLocalPrefix() async throws {
        let service = GeocodingService(locale: japanese) { url in try Self.response(url: url, json: "{}") }
        let results = try await service.search("じょうえつ")
        #expect(results.contains { $0.id == 6825489 })
    }

    @Test func remoteFailureIsNotDisguisedByLocalCandidates() async {
        let service = GeocodingService(locale: japanese) { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: URLError.self) { try await service.search("上越市") }
    }

    @Test func missingIndexKeepsExistingOnlineSearchAvailable() async throws {
        var calls = 0
        let service = GeocodingService(locale: japanese, cityIndex: JapaneseCityIndex(entries: [])) { url in
            calls += 1
            return try Self.response(url: url, json: "{}")
        }
        #expect(try await service.search("上越").isEmpty)
        #expect(calls == 1)
    }

    @Test func cancellationAfterRemoteResponseDoesNotReturnResults() async {
        var response: CheckedContinuation<(Data, URLResponse), Error>?
        var requestURL: URL?
        let service = GeocodingService(locale: japanese) { url in
            requestURL = url
            return try await withCheckedThrowingContinuation { response = $0 }
        }
        let pending = Task { try await service.search("上越市") }
        while response == nil { await Task.yield() }
        pending.cancel()
        do {
            let url = try #require(requestURL)
            response?.resume(returning: try Self.response(url: url, json: "{}"))
        } catch {
            response?.resume(throwing: error)
        }
        await #expect(throws: CancellationError.self) { try await pending.value }
    }

    @Test(arguments: ["", " \n ", "P", "☀"])
    func emptyOrUnsupportedSingleCharacterDoesNotRequest(_ query: String) async throws {
        var calls = 0
        let service = GeocodingService(locale: japanese) { _ in
            calls += 1
            throw URLError(.notConnectedToInternet)
        }
        #expect(try await service.search(query).isEmpty)
        #expect(calls == 0)
    }

    @Test func rapidInputChangeStillClearsShortPrefixResults() async throws {
        let service = GeocodingService(locale: japanese) { url in try Self.response(url: url, json: "{}") }
        let model = CitySearchModel(delay: 0) { try await service.search($0) }
        await model.search("上越").value
        #expect(model.results.contains { $0.id == 6825489 })
        let changed = model.search("横須")
        #expect(model.results.isEmpty && model.isSearching)
        await changed.value
        #expect(model.results.contains { $0.name == "横須賀市" })
        #expect(model.results.allSatisfy { $0.id != 6825489 })
        let pending = model.search("上越")
        model.cancel()
        await pending.value
        #expect(model.results.isEmpty && !model.isSearching && !model.hasFailed)
    }

    private static func response(url: URL, json: String) throws -> (Data, URLResponse) {
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        return (Data(json.utf8), response)
    }
}
