import SwiftUI

/// The square that stands for a meal.
///
/// Imported recipes carry the page's own photography in `heroImageURL`, which was captured,
/// stored, and then only ever drawn inside the recipe editor. Every list in the app stayed
/// emoji-only -- the thing `Meal` itself calls the app's clearest prototype tell. This draws
/// the photo when there is one and falls back to the emoji when there is not, so one change
/// fixes every surface.
struct MealThumbnail: View {
    let emoji: String
    var imageURL: URL?
    var size: CGFloat = AppTheme.emojiTile

    init(meal: Meal?, fallbackEmoji: String = "🍽️", size: CGFloat = AppTheme.emojiTile) {
        emoji = meal?.emoji ?? fallbackEmoji
        imageURL = meal?.heroImageURL
        self.size = size
    }

    init(emoji: String, imageURL: URL? = nil, size: CGFloat = AppTheme.emojiTile) {
        self.emoji = emoji
        self.imageURL = imageURL
        self.size = size
    }

    var body: some View {
        ZStack {
            AppTheme.accentSoft.opacity(0.7)
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        // No spinner and no broken-image chrome: the emoji is a complete
                        // answer, not a placeholder for one.
                        emojiText
                    }
                }
            } else {
                emojiText
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var emojiText: some View {
        Text(emoji).font(.system(size: size * 0.55))
    }
}
