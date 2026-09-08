import SwiftUI

/// One meal in a list.
///
/// Shared by the library and the day picker so the two cannot drift apart, which is how the
/// app ended up drawing the same control three different ways elsewhere.
struct MealRow: View {
    let meal: Meal
    var isFavorite = false
    var note: String?
    var toggleFavorite: (() -> Void)?

    var body: some View {
        HStack(spacing: 13) {
            MealThumbnail(meal: meal)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(meal.name).font(.headline).lineLimit(1)
                    if !meal.isBuiltIn {
                        Text("MINE").font(.caption2.bold()).foregroundStyle(AppTheme.accent)
                    }
                }
                Text(L10n.string("%ld min · %ld servings", meal.prepMinutes, meal.defaultServings))
                    .font(.caption).foregroundStyle(AppTheme.muted)
                if let note {
                    Text(note).font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.warning)
                }
            }
            Spacer(minLength: 0)
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
        .padding(12)
    }
}
