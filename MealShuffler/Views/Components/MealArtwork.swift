import SwiftUI

/// One artwork policy for recipe cards, thumbnails and import previews.
/// Photographs take priority; bundled category illustrations work offline.
struct MealArtwork: View {
    let emoji: String
    var imageURL: URL?
    var tags: Set<MealTag> = []

    init(meal: Meal?, fallbackEmoji: String = "🍽️") {
        emoji = meal?.emoji ?? fallbackEmoji
        imageURL = meal?.heroImageURL
        tags = meal?.tags ?? []
    }

    init(emoji: String, imageURL: URL? = nil, tags: Set<MealTag> = []) {
        self.emoji = emoji
        self.imageURL = imageURL
        self.tags = tags
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppTheme.accentSoft
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        } else {
                            fallback(in: geometry.size)
                        }
                    }
                } else {
                    fallback(in: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func fallback(in size: CGSize) -> some View {
        if let assetName {
            // Fit the whole dish inside landscape heroes as well as square thumbnails.
            Image(assetName).resizable().scaledToFit()
                .frame(width: size.width, height: size.height)
                .background(AppTheme.artworkPaper)
        } else {
            // Custom uncategorized meals and non-cooking day symbols retain their meaning.
            Text(emoji)
                .font(.system(size: min(min(size.width, size.height) * 0.55, 64)))
                .frame(width: size.width, height: size.height)
        }
    }

    private var assetName: String? {
        // Dish form wins over protein: vegetarian pizza should still look like pizza.
        let categories: [(MealTag, String)] = [
            (.pizza, "MealArtPizza"), (.pasta, "MealArtPasta"),
            (.soup, "MealArtSoup"), (.taco, "MealArtTaco"),
            (.fish, "MealArtFish"), (.chicken, "MealArtChicken"),
            (.meat, "MealArtMeat"), (.vegetarian, "MealArtVegetarian")
        ]
        return categories.first(where: { tags.contains($0.0) })?.1
    }
}
