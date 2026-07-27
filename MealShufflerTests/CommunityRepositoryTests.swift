import XCTest
@testable import MealShuffler

final class CommunityRepositoryTests: XCTestCase {
    func testRatingUpdatesAggregatesWithoutDroppingSeedRatings() async throws {
        let suite = "CommunityRepositoryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = LocalCommunityRepository(defaults: defaults)
        let before = try await repository.fetchRecipes()
        let recipe = try XCTUnwrap(before.first)
        let householdID = UUID()

        try await repository.rate(CommunityRating(recipeID: recipe.id, householdID: householdID, stars: 5, wouldCookAgain: true))
        let after = try await repository.fetchRecipes()
        let updated = try XCTUnwrap(after.first(where: { $0.id == recipe.id }))

        XCTAssertEqual(updated.ratingCount, recipe.ratingCount + 1)
        XCTAssertGreaterThanOrEqual(updated.averageRating, recipe.averageRating)
    }
}
