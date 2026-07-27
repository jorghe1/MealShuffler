import Foundation

struct CommunityAuthor: Identifiable, Codable, Hashable {
    let id: UUID
    let displayName: String
}

struct CommunityRecipe: Identifiable, Codable, Hashable {
    let id: UUID
    var meal: Meal
    let author: CommunityAuthor
    let publishedAt: Date
    var averageRating: Double
    var ratingCount: Int
    var cookedCount: Int
    var heroImageURL: URL?
    var attribution: String?

    init(
        id: UUID = UUID(),
        meal: Meal,
        author: CommunityAuthor,
        publishedAt: Date = .now,
        averageRating: Double = 0,
        ratingCount: Int = 0,
        cookedCount: Int = 0,
        heroImageURL: URL? = nil,
        attribution: String? = nil
    ) {
        self.id = id
        self.meal = meal
        self.author = author
        self.publishedAt = publishedAt
        self.averageRating = averageRating
        self.ratingCount = ratingCount
        self.cookedCount = cookedCount
        self.heroImageURL = heroImageURL
        self.attribution = attribution
    }
}

struct CommunityRating: Identifiable, Codable, Hashable {
    let id: UUID
    let recipeID: UUID
    let householdID: UUID
    let stars: Int
    let wouldCookAgain: Bool
    let createdAt: Date

    init(id: UUID = UUID(), recipeID: UUID, householdID: UUID, stars: Int, wouldCookAgain: Bool, createdAt: Date = .now) {
        self.id = id
        self.recipeID = recipeID
        self.householdID = householdID
        self.stars = min(max(stars, 1), 5)
        self.wouldCookAgain = wouldCookAgain
        self.createdAt = createdAt
    }
}

enum CommunityReportReason: String, Codable, CaseIterable, Identifiable {
    case copyright, unsafe, offensive, inaccurate, other
    var id: String { rawValue }
    var name: String {
        switch self {
        case .copyright: L10n.string("Copyright")
        case .unsafe: L10n.string("Unsafe recipe")
        case .offensive: L10n.string("Offensive content")
        case .inaccurate: L10n.string("Errors or omissions")
        case .other: L10n.string("Other")
        }
    }
}

struct CommunityReport: Identifiable, Codable, Hashable {
    let id: UUID
    let recipeID: UUID
    let householdID: UUID
    let reason: CommunityReportReason
    let createdAt: Date

    init(id: UUID = UUID(), recipeID: UUID, householdID: UUID, reason: CommunityReportReason, createdAt: Date = .now) {
        self.id = id
        self.recipeID = recipeID
        self.householdID = householdID
        self.reason = reason
        self.createdAt = createdAt
    }
}
