import SwiftUI

/// The shared square presentation of a meal's photograph or category artwork.
struct MealThumbnail: View {
    private let artwork: MealArtwork
    var size: CGFloat = AppTheme.emojiTile

    init(meal: Meal?, fallbackEmoji: String = "🍽️", size: CGFloat = AppTheme.emojiTile) {
        artwork = MealArtwork(meal: meal, fallbackEmoji: fallbackEmoji)
        self.size = size
    }

    init(emoji: String, imageURL: URL? = nil, size: CGFloat = AppTheme.emojiTile) {
        artwork = MealArtwork(emoji: emoji, imageURL: imageURL)
        self.size = size
    }

    var body: some View {
        artwork
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}
