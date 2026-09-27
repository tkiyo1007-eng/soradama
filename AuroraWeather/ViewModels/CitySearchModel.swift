import Foundation
import Observation

/// 入力と結果を一組で管理し、キャンセルを無視する応答も世代で除外する。
@MainActor
@Observable
final class CitySearchModel {
    private(set) var results: [GeoPlace] = []
    private(set) var isSearching = false
    private(set) var hasFailed = false
    private var generation = 0
    private var task: Task<Void, Never>?
    private let lookup: (String) async throws -> [GeoPlace]
    private let delay: UInt64

    init(delay: UInt64 = 350_000_000,
         lookup: @escaping (String) async throws -> [GeoPlace] = { try await GeocodingService().search($0) }) {
        self.delay = delay
        self.lookup = lookup
    }

    @discardableResult
    func search(_ text: String) -> Task<Void, Never> {
        cancel()
        results = []
        hasFailed = false
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = generation
        isSearching = !query.isEmpty
        let task = Task { [weak self] in
            guard let self, !query.isEmpty else { return }
            do {
                try await Task.sleep(nanoseconds: delay)
                try Task.checkCancellation()
                let found = try await lookup(query)
                guard token == generation, !Task.isCancelled else { return }
                results = found
                isSearching = false
            } catch {
                guard token == generation, !Task.isCancelled else { return }
                hasFailed = true
                isSearching = false
            }
        }
        self.task = task
        return task
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isSearching = false
    }
}
