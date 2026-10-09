import Foundation

/// The household side of the store: who cooks, what the kids wish for, photos of what was
/// cooked, and what the year looked like.
extension AppStore {
    // MARK: - Who cooks

    /// The member cooking on a day, if one was chosen.
    func cook(for day: Weekday, nextWeek: Bool = false) -> HouseholdMember? {
        guard let id = context(for: day, nextWeek: nextWeek).cookMemberID else { return nil }
        return household.members.first { $0.id == id }
    }

    /// Who cooks is about the day, not the dish, so it survives a reshuffle of that day.
    func setCook(_ memberID: UUID?, for day: Weekday, nextWeek: Bool = false) {
        var context = self.context(for: day, nextWeek: nextWeek)
        guard context.cookMemberID != memberID else { return }
        context.cookMemberID = memberID
        if nextWeek { nextWeekContexts[day] = context } else { dayContexts[day] = context }
    }

    // MARK: - Wishes and votes from the kids view

    var pendingWishes: [MealWish] { householdTools.wishes ?? [] }

    /// A member's wish this week, if they made one.
    func wish(from member: HouseholdMember) -> MealWish? {
        pendingWishes.first { $0.memberID == member.id }
    }

    /// One wish per child at a time: a new wish replaces the last one.
    func addWish(_ meal: Meal, from member: HouseholdMember) {
        var wishes = pendingWishes.filter { $0.memberID != member.id }
        wishes.append(MealWish(memberID: member.id, mealID: meal.id))
        householdTools.wishes = wishes
    }

    /// A grown-up's answer: put the dish on a day of next week, or let it go.
    func resolveWish(_ wish: MealWish, plannedOn day: Weekday?) {
        if let day, let meal = meal(id: wish.mealID) {
            setNextWeekMeal(meal, on: day)
        }
        householdTools.wishes = pendingWishes.filter { $0.id != wish.id }
    }

    /// Dishes to vote on: ones this member has no opinion about yet, the same set all week so
    /// a vote does not reshuffle the cards under a child's finger.
    func voteCandidates(for member: HouseholdMember, count: Int = 6) -> [Meal] {
        let opinions = memberPreferences[member.id] ?? [:]
        let planned = Set((plan.meals + (nextWeekPlan?.meals ?? [])).compactMap(\.mealID))
        let seed = Int(plan.startDate.timeIntervalSince1970 / 86_400)
        let open = meals.filter { opinions[$0.id] == nil && !planned.contains($0.id) }
        let pool = open.isEmpty ? meals.filter { !planned.contains($0.id) } : open
        return Array(pool.sorted { stableRank($0.id, seed) < stableRank($1.id, seed) }.prefix(count))
    }

    private func stableRank(_ id: UUID, _ seed: Int) -> Int {
        // Deterministic within a week, different between weeks; not cryptographic.
        var value = seed &* 31
        for byte in id.uuidString.utf8 { value = value &* 131 &+ Int(byte) }
        return value
    }

    // MARK: - Photos

    /// Keeps the household's own photo of a dish, which then shows wherever the dish does.
    @discardableResult
    func savePhoto(_ data: Data, for meal: Meal) -> Bool {
        do {
            let prepared = try RecipeImagePreparation.prepare(data)
            guard let name = try RecipeLibraryStorage.saveImages([prepared], recipeID: meal.id).first else { return false }
            var updated = self.meal(id: meal.id) ?? meal
            updated.photoName = name
            return saveMeal(updated)
        } catch {
            persistenceError = error.localizedDescription
            return false
        }
    }

    // MARK: - Rules that leave little choice

    /// Days this week's required rules leave two or fewer dinners for. Shuffles on those days
    /// repeat themselves, which looks like the app is broken when it is the rules.
    func tightDays(threshold: Int = 2) -> [(day: Weekday, count: Int)] {
        let active = rules.filter { $0.isActive(inWeek: plan.startDate) && $0.strength == .required }
        return Weekday.ordered().compactMap { day -> (day: Weekday, count: Int)? in
            let context = self.context(for: day)
            guard context.mode == .cook else { return nil }
            if active.contains(where: { rule in
                if case .dinnerMode(let scope, let mode) = rule.constraint { return scope.covers(day) && mode != .cook }
                return false
            }) { return nil }
            let fitting = meals.filter { meal in
                active.allSatisfy { rule in
                    switch rule.constraint {
                    case .requiredOn(let scope, let matcher):
                        return !scope.covers(day) || matcher.matches(meal, context: matchContext.forDay(day))
                    case .excludedOn(let scope, let matcher):
                        return !scope.covers(day) || !matcher.matches(meal, context: matchContext.forDay(day))
                    case .maximumPrepTime(let scope, let minutes):
                        return !scope.covers(day) || (meal.prepMinutes > 0 && meal.prepMinutes <= minutes)
                    case .maximumPerWeek(let matcher, 0):
                        return !matcher.matches(meal, context: matchContext)
                    default:
                        return true
                    }
                }
            }.count
            return fitting <= threshold ? (day: day, count: fitting) : nil
        }
    }

    // MARK: - Middagsåret

    /// What a year of dinners added up to, from what was marked cooked.
    func yearSummary(for year: Int = Calendar.current.component(.year, from: .now)) -> YearSummary {
        let calendar = Calendar.current
        let cooked = feedbackEvents.filter { event in
            event.kind == .cooked && calendar.component(.year, from: event.plannedDate ?? event.timestamp) == year
        }
        var counts: [UUID: Int] = [:]
        var names: [UUID: String] = [:]
        var tagCounts: [MealTag: Int] = [:]
        var firstCooked: [UUID: Date] = [:]
        for event in cooked {
            counts[event.mealID, default: 0] += 1
            let recipe = event.recipeSnapshot ?? meal(id: event.mealID)
            if let recipe {
                names[event.mealID] = recipe.name
                for tag in recipe.tags { tagCounts[tag, default: 0] += 1 }
            }
            let date = event.plannedDate ?? event.timestamp
            if let existing = firstCooked[event.mealID], existing <= date { continue }
            firstCooked[event.mealID] = date
        }
        // A dish is new this year when nothing earlier in the history cooked it.
        let earlier = Set(feedbackEvents.filter { event in
            event.kind == .cooked && calendar.component(.year, from: event.plannedDate ?? event.timestamp) < year
        }.map(\.mealID))
        // Most cooked first; equal counts by name, so the order is the same every time.
        let ranked: [(name: String, count: Int)] = counts.compactMap { entry in
            names[entry.key].map { (name: $0, count: entry.value) }
        }
        let top = ranked.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.name < rhs.name
        }.prefix(3)
        let weekdays = Dictionary(grouping: cooked.compactMap(\.weekday), by: { $0 }).mapValues(\.count)
        return YearSummary(
            year: year,
            dinners: cooked.count,
            distinctDishes: counts.count,
            newDishes: counts.keys.filter { !earlier.contains($0) }.count,
            fish: tagCounts[.fish] ?? 0,
            vegetarian: tagCounts[.vegetarian] ?? 0,
            top: top.map { YearSummary.Dish(name: $0.name, count: $0.count) },
            busiestWeekday: weekdays.max { $0.value < $1.value }?.key
        )
    }
}

/// A year of dinners, for the summary screen and the picture it shares.
struct YearSummary: Equatable {
    struct Dish: Equatable, Hashable {
        let name: String
        let count: Int
    }

    let year: Int
    let dinners: Int
    let distinctDishes: Int
    let newDishes: Int
    let fish: Int
    let vegetarian: Int
    let top: [Dish]
    let busiestWeekday: Weekday?
}
