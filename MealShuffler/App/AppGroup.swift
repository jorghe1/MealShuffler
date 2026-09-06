import Foundation

/// The container the app and its extensions share.
///
/// State lived in `UserDefaults.standard`, which is private to the app process. A widget or a
/// share extension is a separate process and cannot see it, so anything they need has to move
/// into an App Group container.
///
/// Requires the App Groups capability on the App ID and on every extension's profile. When the
/// entitlement is missing — an unsigned test run, a profile that was not regenerated — the
/// suite cannot be opened, and falling back keeps the app working rather than starting empty.
enum AppGroup {
    static let identifier = "group.no.mealshuffler.shared"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// True when the shared container is actually available. Extensions rely on it; the app
    /// only degrades to a private container.
    static var isAvailable: Bool {
        UserDefaults(suiteName: identifier) != nil
    }
}
