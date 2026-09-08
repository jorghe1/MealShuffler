import Foundation

/// The three ways to narrow a meal list. Shared by the library and the day picker.
enum MealFilter: String, CaseIterable, Identifiable {
    case all, favourites, mine

    var id: String { rawValue }

    var name: String {
        switch self {
        case .all: L10n.string("All")
        case .favourites: L10n.string("Favourites")
        case .mine: L10n.string("Mine")
        }
    }

    func matches(_ meal: Meal, favorites: Set<UUID>) -> Bool {
        switch self {
        case .all: true
        case .favourites: favorites.contains(meal.id)
        case .mine: !meal.isBuiltIn
        }
    }
}

extension Meal {
    /// Free-text match across the fields someone would actually type.
    ///
    /// Ingredients are included because "what can I make with spinach" is the question
    /// people have.
    func matches(searchText: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(searchText)
            || subtitle.localizedCaseInsensitiveContains(searchText)
            || tags.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
            || ingredients.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}
