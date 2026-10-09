import Foundation

/// The app's tabs. Four, ordered by the weekly loop: plan the week, pick dishes, shop, and the
/// family the rules belong to.
enum AppTab: Hashable {
    case week
    case meals
    case shop
    case family
}

/// Where the app should be showing, for anything that needs to move it there: a notification,
/// a widget, a link.
///
/// `TabView` had no selection binding, so tapping "Shopping day" opened the app wherever it
/// was last left.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var tab: AppTab = .week
    /// The Week tab shows next week rather than this one.
    @Published var showsNextWeek = false

    func open(_ destination: ReminderDestination) {
        switch destination {
        case .tonight:
            tab = .week
            showsNextWeek = false
        case .nextWeek:
            tab = .week
            showsNextWeek = true
        case .shop:
            tab = .shop
        }
    }

    /// `mealshuffler://week`, `mealshuffler://next-week`, `mealshuffler://shop` -- what the
    /// widget links to. Returns false for any other URL, which the caller handles.
    func open(_ url: URL) -> Bool {
        guard url.scheme == "mealshuffler" else { return false }
        switch url.host {
        case "week", "tonight": open(.tonight)
        case "next-week": open(.nextWeek)
        case "shop": open(.shop)
        default: return false
        }
        return true
    }
}

/// The one store the scene, notification actions and background refresh all share.
///
/// The scene used to build its own, and notification actions waited for the scene to hand
/// theirs a handler -- which a lock-screen "We cooked this" launches without, so the tap sat in
/// a buffer until the app was next opened, or was lost. Two stores would write the same file
/// over each other.
@MainActor
enum AppStoreHost {
    static let shared = AppStore()
}
