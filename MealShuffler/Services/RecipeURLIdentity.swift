import Foundation

enum RecipeURLIdentity {
    static func normalized(_ url: URL) -> String {
        guard var value = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url.absoluteString }
        value.fragment = nil; value.host = value.host?.lowercased()
        value.queryItems = value.queryItems?.filter {
            !$0.name.lowercased().hasPrefix("utm_") && !["fbclid", "gclid", "mc_cid", "mc_eid"].contains($0.name.lowercased())
        }.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        if value.queryItems?.isEmpty == true { value.queryItems = nil }
        if value.path.count > 1, value.path.hasSuffix("/") { value.path.removeLast() }
        return value.string ?? url.absoluteString
    }
}
