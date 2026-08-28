import Foundation

enum SoradamaURL {
    static let scheme = "soradama"
    static let collectionHost = "collection"
    static let collection = URL(string: "\(scheme)://\(collectionHost)")!

    static func opensCollection(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme?.lowercased() == scheme &&
            components.host?.lowercased() == collectionHost &&
            components.user == nil &&
            components.password == nil &&
            components.port == nil &&
            components.path.isEmpty &&
            components.query == nil &&
            components.fragment == nil
    }
}
