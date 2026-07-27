import Combine
import Foundation

protocol CommunityRepository: Sendable {
    func fetchRecipes() async throws -> [CommunityRecipe]
    func publish(meal: Meal, author: CommunityAuthor) async throws -> CommunityRecipe
    func rate(_ rating: CommunityRating) async throws
    func report(_ report: CommunityReport) async throws
}

actor LocalCommunityRepository: CommunityRepository {
    private var recipes: [CommunityRecipe]
    private var ratings: [CommunityRating]
    private var reports: [CommunityReport]
    private let defaults: UserDefaults
    private let recipesKey = "meal-shuffler-community-recipes-v1"
    private let ratingsKey = "meal-shuffler-community-ratings-v1"
    private let reportsKey = "meal-shuffler-community-reports-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: recipesKey),
           let saved = try? JSONDecoder().decode([CommunityRecipe].self, from: data) {
            recipes = saved
        } else {
            recipes = Self.seedRecipes
        }
        if let data = defaults.data(forKey: ratingsKey),
           let saved = try? JSONDecoder().decode([CommunityRating].self, from: data) {
            ratings = saved
        } else {
            ratings = []
        }
        if let data = defaults.data(forKey: reportsKey),
           let saved = try? JSONDecoder().decode([CommunityReport].self, from: data) {
            reports = saved
        } else {
            reports = []
        }
    }

    func fetchRecipes() async throws -> [CommunityRecipe] {
        recipes.sorted { lhs, rhs in
            if lhs.ratingCount != rhs.ratingCount { return lhs.averageRating > rhs.averageRating }
            return lhs.publishedAt > rhs.publishedAt
        }
    }

    func publish(meal: Meal, author: CommunityAuthor) async throws -> CommunityRecipe {
        let attribution: String?
        if case .web(let url) = meal.source { attribution = url.absoluteString } else { attribution = nil }
        let recipe = CommunityRecipe(meal: meal, author: author, attribution: attribution)
        recipes.insert(recipe, at: 0)
        persist()
        return recipe
    }

    func rate(_ rating: CommunityRating) async throws {
        let priorRating = ratings.first { $0.recipeID == rating.recipeID && $0.householdID == rating.householdID }
        ratings.removeAll { $0.recipeID == rating.recipeID && $0.householdID == rating.householdID }
        ratings.append(rating)
        guard let index = recipes.firstIndex(where: { $0.id == rating.recipeID }) else { return }
        let oldCount = recipes[index].ratingCount
        let oldTotal = recipes[index].averageRating * Double(oldCount)
        if let priorRating, oldCount > 0 {
            recipes[index].averageRating = (oldTotal - Double(priorRating.stars) + Double(rating.stars)) / Double(oldCount)
        } else {
            recipes[index].ratingCount = oldCount + 1
            recipes[index].averageRating = (oldTotal + Double(rating.stars)) / Double(oldCount + 1)
        }
        persist()
    }

    func report(_ report: CommunityReport) async throws {
        guard !reports.contains(where: { $0.recipeID == report.recipeID && $0.householdID == report.householdID }) else { return }
        reports.append(report)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(recipes) { defaults.set(data, forKey: recipesKey) }
        if let data = try? JSONEncoder().encode(ratings) { defaults.set(data, forKey: ratingsKey) }
        if let data = try? JSONEncoder().encode(reports) { defaults.set(data, forKey: reportsKey) }
    }

    private static let seedRecipes: [CommunityRecipe] = {
        let nordli = CommunityAuthor(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, displayName: L10n.string("The Nordli family"))
        let berg = CommunityAuthor(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, displayName: L10n.string("Berg's kitchen"))
        let sol = CommunityAuthor(id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, displayName: "Sol & Co")
        return [
            CommunityRecipe(meal: SampleMeals.all[1], author: nordli, publishedAt: .now.addingTimeInterval(-86_400 * 2), averageRating: 4.8, ratingCount: 12, cookedCount: 31),
            CommunityRecipe(meal: SampleMeals.all[6], author: berg, publishedAt: .now.addingTimeInterval(-86_400 * 5), averageRating: 4.6, ratingCount: 8, cookedCount: 19),
            CommunityRecipe(meal: SampleMeals.all[11], author: sol, publishedAt: .now.addingTimeInterval(-86_400 * 8), averageRating: 4.4, ratingCount: 5, cookedCount: 14)
        ]
    }()
}

@MainActor
final class CommunityStore: ObservableObject {
    @Published private(set) var recipes: [CommunityRecipe] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    private let repository: any CommunityRepository

    init(repository: any CommunityRepository = LocalCommunityRepository()) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do { recipes = try await repository.fetchRecipes() }
        catch { errorMessage = error.localizedDescription }
    }

    func publish(meal: Meal, household: Household) async -> Bool {
        do {
            _ = try await repository.publish(meal: meal, author: CommunityAuthor(id: household.id, displayName: household.name))
            recipes = try await repository.fetchRecipes()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func rate(recipeID: UUID, householdID: UUID, stars: Int, wouldCookAgain: Bool) async {
        do {
            try await repository.rate(CommunityRating(recipeID: recipeID, householdID: householdID, stars: stars, wouldCookAgain: wouldCookAgain))
            recipes = try await repository.fetchRecipes()
        } catch { errorMessage = error.localizedDescription }
    }

    func report(recipeID: UUID, householdID: UUID, reason: CommunityReportReason) async -> Bool {
        do {
            try await repository.report(CommunityReport(recipeID: recipeID, householdID: householdID, reason: reason))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
