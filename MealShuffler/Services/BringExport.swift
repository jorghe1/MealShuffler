import Foundation

/// A way into Bring!, the shopping list a lot of Norwegian households already share.
///
/// Bring imports from a URL it fetches and parses itself: a page carrying schema.org recipe
/// markup, or a `.json` file in its own import format. Its documented integrations -- the
/// button on recipe sites, and the app-to-app deeplink -- are both that same shape, and
/// neither takes a plain list of items. So the week's aggregated shopping list, scaled to the
/// diners and with staples and what is already at home taken out, is not something Bring can
/// be handed; sending it would mean publishing it at a public URL for Bring to come and read,
/// which is a much larger decision than a menu item. What can be sent is a dinner the
/// household imported from a link: Bring re-reads that page and adds its ingredients, exactly
/// as its own button does on Norwegian recipe sites.
///
/// The app-to-app variant additionally asks for a hashed advertising identifier. It is not
/// used here: it is an ad-attribution field, it would drag in App Tracking Transparency, and
/// the plain deeplink works without it.
enum BringExport {
    private static let deeplinkEndpoint = "https://api.getbring.com/rest/bringrecipes/deeplink"

    /// The link that opens Bring! on this recipe, or nil for a meal Bring cannot read.
    ///
    /// Nil is the common case and not a failure: a built-in meal, one typed in by hand, one
    /// scanned off a page and one pasted in all have no address for Bring to fetch.
    static func deeplink(for meal: Meal, servings: Int? = nil) -> URL? {
        guard case .web(let source) = meal.source,
              let scheme = source.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              var components = URLComponents(string: deeplinkEndpoint) else { return nil }

        let base = max(meal.defaultServings, 1)
        components.queryItems = [
            URLQueryItem(name: "url", value: source.absoluteString),
            URLQueryItem(name: "source", value: "web"),
            URLQueryItem(name: "baseQuantity", value: String(base)),
            URLQueryItem(name: "requestedQuantity", value: String(max(servings ?? base, 1)))
        ]
        return components.url
    }

    /// One dinner that can go, named rather than a tuple so a list can identify it.
    struct Dinner: Identifiable, Hashable {
        let meal: Meal
        let link: URL

        var id: UUID { meal.id }
    }

    /// This week's dinners that Bring can read, in the order they are cooked.
    static func exportableDinners(plan: WeeklyPlan, meals: [Meal]) -> [Dinner] {
        let order = Weekday.ordered()
        return plan.meals
            .sorted { (order.firstIndex(of: $0.day) ?? 0) < (order.firstIndex(of: $1.day) ?? 0) }
            .compactMap { planned in
                guard planned.kind == .meal,
                      let id = planned.mealID,
                      let meal = meals.first(where: { $0.id == id }),
                      let link = deeplink(for: meal, servings: planned.servings) else { return nil }
                return Dinner(meal: meal, link: link)
            }
    }
}
