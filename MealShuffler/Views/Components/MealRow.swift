import SwiftUI

/// One meal in a list.
///
/// Shared by the library and the day picker so the two cannot drift apart, which is how the
/// app ended up drawing the same control three different ways elsewhere.
struct MealRow: View {
    let meal: Meal
    var isFavorite = false
    /// Off for the library's "names only" view.
    var showsThumbnail = true
    var note: String?
    var openMeal: (() -> Void)?
    var toggleFavorite: (() -> Void)?

    var body: some View {
        HStack(spacing: 13) {
            if let openMeal {
                Button(action: openMeal) { mealContent }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("View recipe: %@", meal.name))
            } else { mealContent }
            if let toggleFavorite {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? AppTheme.destructive : AppTheme.muted)
                        .iconButtonFrame()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isFavorite ? L10n.string("Remove family favorite") : L10n.string("Mark as family favorite")
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, showsThumbnail ? 12 : 6)
    }

    /// "0 min" read as instant; an unknown time says so, as it does on the library cards.
    private var metadata: String {
        meal.prepMinutes > 0
            ? L10n.string("%ld min · %ld servings", meal.prepMinutes, meal.defaultServings)
            : L10n.string("Time not specified · %ld servings", meal.defaultServings)
    }
    private var mealContent: some View {
        HStack(spacing: 13) {
            if showsThumbnail { MealThumbnail(meal: meal) }
            VStack(alignment: .leading, spacing: showsThumbnail ? 4 : 2) {
                // No "MINE" tag: the Mine filter already says whose recipe it is, and a shouting
                // label on every row of a library that is mostly the household's own was noise.
                Text(meal.name).font(.headline).lineLimit(2)
                Text(metadata)
                    .font(.caption).foregroundStyle(AppTheme.muted)
                if let note {
                    Text(note).font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.warning)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }

}
