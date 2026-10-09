import SwiftUI
import UIKit

/// One artwork policy for recipe cards, thumbnails and import previews.
///
/// In order: the household's own photo of the dish, the imported recipe photo, a hand-made
/// drawing dropped into the asset catalog as "Dish-<meal id>", the drawn dish form, and the
/// emoji only for days nobody cooks (away, takeaway, leftovers).
struct MealArtwork: View {
    let emoji: String
    var imageURL: URL?
    var tags: Set<MealTag> = []
    /// The household's own photo, a file in the recipe image folder.
    private var photoName: String?
    private var photo: UIImage?
    private var assetOverride: UIImage?
    /// Nil keeps the emoji: a non-cooking day, or a recipe preview with no category yet.
    private var form: DishForm?
    private var palette: DishPalette?

    init(meal: Meal?, fallbackEmoji: String = "🍽️") {
        emoji = meal?.emoji ?? fallbackEmoji
        imageURL = meal?.heroImageURL
        tags = meal?.tags ?? []
        if let meal {
            photoName = meal.photoName
            photo = meal.photoName.flatMap { DishPhotoCache.shared.image(named: $0) }
            assetOverride = UIImage(named: "Dish-" + meal.id.uuidString)
            let inferred = DishForm.form(for: meal)
            form = inferred
            palette = DishPalette(meal: meal, form: inferred)
        }
    }

    init(emoji: String, imageURL: URL? = nil, tags: Set<MealTag> = []) {
        self.emoji = emoji
        self.imageURL = imageURL
        self.tags = tags
        // The share poster and the recipe editor only know the tags. Tags that say nothing
        // about the dish (quick, weekend) would give a bare plate; the chosen emoji says more.
        let inferred = DishForm.form(name: "", tags: tags)
        if !tags.isEmpty && inferred != .plate {
            form = inferred
            palette = DishPalette(form: inferred, name: "", tags: tags, ingredientNames: [])
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppTheme.accentSoft
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else if let imageURL {
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
        if let assetOverride {
            // Fit the whole drawing inside landscape heroes as well as square thumbnails.
            Image(uiImage: assetOverride).resizable().scaledToFit()
                .frame(width: size.width, height: size.height)
                .background(AppTheme.artworkPaper)
        } else if let form {
            DishIllustration(form: form, palette: palette)
                .frame(width: size.width, height: size.height)
        } else {
            // Non-cooking day symbols keep their meaning.
            Text(emoji)
                .font(.system(size: min(min(size.width, size.height) * 0.55, 64)))
                .frame(width: size.width, height: size.height)
        }
    }
}

/// Decoded household photos, so a row does not read and decode its JPEG every time SwiftUI
/// rebuilds the view. NSCache is itself thread-safe and drops images under memory pressure.
private final class DishPhotoCache: @unchecked Sendable {
    static let shared = DishPhotoCache()
    private let images = NSCache<NSString, UIImage>()

    func image(named name: String) -> UIImage? {
        if let cached = images.object(forKey: name as NSString) { return cached }
        guard let data = RecipeLibraryStorage.image(named: name), let image = UIImage(data: data) else { return nil }
        images.setObject(image, forKey: name as NSString)
        return image
    }
}
