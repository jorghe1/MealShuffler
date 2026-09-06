import Foundation

/// Everything the generator knows about what this household likes.
///
/// Bundled so the signal set can grow (per-member preferences, seasonality) without the
/// generator's parameter list growing with it.
struct TasteProfile {
    var favoriteMealIDs: Set<UUID> = []
    /// Swiped right during onboarding. A softer signal than an explicitly hearted favourite.
    var likedMealIDs: Set<UUID> = []
    /// Swiped left. Normally filtered out upstream, but still penalised here because the
    /// generator falls back to the full library when rules cannot otherwise be satisfied.
    var dislikedMealIDs: Set<UUID> = []
    var learnedScores: [UUID: Int] = [:]
    var recentlyCookedMealIDs: Set<UUID> = []

    static let empty = TasteProfile()
}

struct MealPlanGenerator {
    /// Softmax temperature, in score points.
    ///
    /// Sets how sharply score differences translate into selection odds: two meals `d` points
    /// apart are picked in a ratio of `exp(d / temperature)`. At 30 the repetition penalty
    /// (100) is a ~28x deterrent, so weeks essentially never repeat a meal, while the strongest
    /// possible taste signal (30) is only ~2.7x, so a well-liked meal is favoured without
    /// crowding the library out. Calibrated against simulated households: a fresh install is
    /// near-uniform, and even a heavily-used profile keeps its top meal near 28% with every
    /// meal still reachable.
    private static let temperature = 30.0

    private let random: RandomSource

    /// The week in the order this locale runs it.
    ///
    /// Generation order, "yesterday's dinner" and leftovers sourcing all depend on the real
    /// sequence of days, not on the Monday-first declaration order of `Weekday`.
    private let orderedDays: [Weekday]

    init(random: RandomSource = SystemRandomSource(), orderedDays: [Weekday] = Weekday.ordered()) {
        self.random = random
        self.orderedDays = orderedDays.isEmpty ? Weekday.allCases : orderedDays
    }

    func generate(
        preferredMeals: [Meal],
        allMeals: [Meal],
        rules: [PlanningRule],
        contexts: [Weekday: DayPlanContext] = [:],
        taste: TasteProfile = .empty,
        existingPlan: WeeklyPlan = .empty,
        avoidingMealOnDay: [Weekday: UUID] = [:],
        swapIntents: [Weekday: MealSwapIntent] = [:]
    ) -> GenerationResult {
        let activeRules = rules.filter(\.isEnabled)
        let requiredRules = activeRules.filter { $0.strength == .required }
        let preferredRules = activeRules.filter { $0.strength == .preferred }
        var selected: [Weekday: Meal] = [:]
        var entries: [Weekday: PlannedMeal] = [:]
        var lockedDays = Set<Weekday>()
        var conflicts: [PlanConflict] = []

        for item in existingPlan.meals where item.isLocked {
            entries[item.day] = item
            lockedDays.insert(item.day)
            if let mealID = item.mealID, let meal = allMeals.first(where: { $0.id == mealID }) {
                selected[item.day] = meal
            }
        }

        for day in orderedDays where entries[day] == nil {
            let context = contexts[day] ?? DayPlanContext()
            switch context.mode {
            case .away:
                entries[day] = PlannedMeal(day: day, mealID: nil, isLocked: false, servings: 0, kind: .away)
                continue
            case .takeaway:
                entries[day] = PlannedMeal(day: day, mealID: nil, isLocked: false, servings: context.diners, kind: .takeaway)
                continue
            case .leftovers:
                if let source = resolveLeftoverSource(for: day, context: context, selected: selected),
                   let sourceMeal = selected[source] {
                    selected[day] = sourceMeal
                    entries[day] = PlannedMeal(
                        day: day,
                        mealID: sourceMeal.id,
                        isLocked: false,
                        servings: context.diners,
                        kind: .leftovers(sourceDay: source)
                    )
                    let availableExtras = (contexts[source] ?? DayPlanContext()).extraServings
                    if availableExtras < context.diners {
                        conflicts.append(PlanConflict(
                            message: L10n.string(
                                "%ld extra servings are made on %@, but %ld people will eat leftovers on %@.",
                                availableExtras,
                                source.name.lowercased(),
                                context.diners,
                                day.name.lowercased()
                            ),
                            suggestion: L10n.string("Increase the number of extra servings on %@.", source.name.lowercased())
                        ))
                    }
                } else {
                    entries[day] = PlannedMeal(day: day, mealID: nil, isLocked: false, servings: context.diners, kind: .leftovers(sourceDay: context.leftoverSourceDay ?? day))
                    conflicts.append(PlanConflict(
                        message: L10n.string("%@ is set to leftovers, but no earlier dinner can be used.", day.name),
                        suggestion: L10n.string("Choose an earlier day and make extra servings.")
                    ))
                }
                continue
            case .cook:
                break
            }

            let currentMeal = avoidingMealOnDay[day].flatMap { id in allMeals.first(where: { $0.id == id }) }
            let intent = swapIntents[day]
            let preferred = candidatePool(
                for: day,
                from: preferredMeals,
                selected: selected,
                rules: requiredRules,
                context: context,
                avoiding: avoidingMealOnDay[day],
                intent: intent,
                currentMeal: currentMeal,
                favoriteMealIDs: taste.favoriteMealIDs,
                enforceWeeklyMaximums: true
            )
            let fallback = candidatePool(
                for: day,
                from: allMeals,
                selected: selected,
                rules: requiredRules,
                context: context,
                avoiding: avoidingMealOnDay[day],
                intent: intent,
                currentMeal: currentMeal,
                favoriteMealIDs: taste.favoriteMealIDs,
                enforceWeeklyMaximums: true
            )
            let relaxed = candidates(
                for: day,
                from: allMeals,
                selected: selected,
                rules: requiredRules,
                context: context,
                avoiding: nil,
                enforceWeeklyMaximums: false
            )
            let pool = !preferred.isEmpty ? preferred : (!fallback.isEmpty ? fallback : relaxed)

            if let meal = chooseMeal(
                from: pool,
                day: day,
                selected: selected,
                preferredRules: preferredRules,
                taste: taste,
                intent: intent
            ) {
                selected[day] = meal
                entries[day] = PlannedMeal(
                    day: day,
                    mealID: meal.id,
                    isLocked: false,
                    servings: context.cookedServings,
                    kind: .meal
                )
            }
        }

        satisfyWeeklyMinimums(
            selected: &selected,
            entries: &entries,
            lockedDays: lockedDays,
            preferredMeals: preferredMeals,
            allMeals: allMeals,
            rules: requiredRules,
            contexts: contexts
        )

        let plan = WeeklyPlan(meals: orderedDays.compactMap { entries[$0] })
        conflicts.append(contentsOf: validate(plan: plan, allMeals: allMeals, rules: requiredRules, contexts: contexts))

        // Not a rule violation: the plan is valid, it just had to reach past the meals this
        // household has expressed an opinion about. Marked informational so it stops being
        // counted and coloured as a broken rule.
        let preferredIDs = Set(preferredMeals.map(\.id))
        let fallbackNames = selected.values
            .filter { !preferredIDs.contains($0.id) }
            .map(\.name)
            .uniqued()
            .sorted()
        if !fallbackNames.isEmpty {
            conflicts.append(PlanConflict(
                message: L10n.string("To satisfy your rules we also used: %@.", fallbackNames.joined(separator: ", ")),
                suggestion: L10n.string("Add more meals in these categories to get more choice."),
                severity: .informational
            ))
        }

        return GenerationResult(plan: plan, conflicts: conflicts.uniqued(by: \.message))
    }

    private func resolveLeftoverSource(
        for day: Weekday,
        context: DayPlanContext,
        selected: [Weekday: Meal]
    ) -> Weekday? {
        if let requested = context.leftoverSourceDay, selected[requested] != nil { return requested }
        guard let index = orderedDays.firstIndex(of: day), index > 0 else { return nil }
        return orderedDays[..<index].reversed().first(where: { selected[$0] != nil })
    }

    private func candidatePool(
        for day: Weekday,
        from meals: [Meal],
        selected: [Weekday: Meal],
        rules: [PlanningRule],
        context: DayPlanContext,
        avoiding: UUID?,
        intent: MealSwapIntent?,
        currentMeal: Meal?,
        favoriteMealIDs: Set<UUID>,
        enforceWeeklyMaximums: Bool
    ) -> [Meal] {
        let base = candidates(
            for: day,
            from: meals,
            selected: selected,
            rules: rules,
            context: context,
            avoiding: avoiding,
            enforceWeeklyMaximums: enforceWeeklyMaximums
        )
        guard let intent else { return base }

        let refined: [Meal]
        switch intent {
        case .different, .surprise:
            refined = base
        case .quicker:
            refined = currentMeal.map { current in base.filter { $0.prepMinutes < current.prepMinutes } } ?? base
        case .cheaper:
            refined = currentMeal.map { current in base.filter { $0.planningCost < current.planningCost } } ?? base
        case .favorite:
            refined = base.filter { favoriteMealIDs.contains($0.id) }
        }
        return refined.isEmpty ? base : refined
    }

    private func candidates(
        for day: Weekday,
        from meals: [Meal],
        selected: [Weekday: Meal],
        rules: [PlanningRule],
        context: DayPlanContext,
        avoiding: UUID?,
        enforceWeeklyMaximums: Bool
    ) -> [Meal] {
        meals.filter { meal in
            if meal.id == avoiding { return false }
            if let maximum = context.maximumPrepMinutes, meal.prepMinutes > maximum { return false }
            guard allows(meal: meal, on: day, rules: rules) else { return false }
            return !enforceWeeklyMaximums || !exceedsMaximum(meal: meal, selected: selected, rules: rules)
        }
    }

    private func allows(meal: Meal, on day: Weekday, rules: [PlanningRule]) -> Bool {
        for rule in rules {
            switch rule.constraint {
            case .requiredOn(let requiredDay, let matcher) where requiredDay == day:
                if !matcher.matches(meal) { return false }
            case .excludedOn(let excludedDay, let matcher) where excludedDay == day:
                if matcher.matches(meal) { return false }
            case .maximumPrepTime(let limitedDay, let minutes) where limitedDay == day:
                if meal.prepMinutes > minutes { return false }
            default:
                continue
            }
        }
        return true
    }

    private func exceedsMaximum(meal: Meal, selected: [Weekday: Meal], rules: [PlanningRule]) -> Bool {
        for rule in rules {
            guard case .maximumPerWeek(let matcher, let maximum) = rule.constraint,
                  matcher.matches(meal) else { continue }
            if selected.values.filter(matcher.matches).count >= maximum { return true }
        }
        return false
    }

    /// Scores every candidate, then *samples* from the resulting distribution.
    ///
    /// This used to take `max(by:)` over scores carrying a `0...30` random jitter, which made
    /// selection an argmax in all but name: the jitter was small next to the taste terms, so a
    /// household that had marked a few meals cooked converged on one answer per day and the
    /// shuffle stopped shuffling. Sampling keeps the same scores meaningful while leaving every
    /// candidate reachable.
    private func chooseMeal(
        from meals: [Meal],
        day: Weekday,
        selected: [Weekday: Meal],
        preferredRules: [PlanningRule],
        taste: TasteProfile,
        intent: MealSwapIntent?
    ) -> Meal? {
        guard !meals.isEmpty else { return nil }
        guard meals.count > 1 else { return meals.first }
        let usedIDs = Set(selected.values.map(\.id))
        let previousMeal: Meal? = {
            guard let index = orderedDays.firstIndex(of: day), index > 0 else { return nil }
            return selected[orderedDays[index - 1]]
        }()

        let scored = meals.map { meal -> (meal: Meal, score: Double) in
            var score = 0.0
            if !usedIDs.contains(meal.id) { score += intent == .surprise ? 180 : 100 }
            if let previousMeal, meal.tags.isDisjoint(with: previousMeal.tags) { score += 25 }
            if taste.favoriteMealIDs.contains(meal.id) { score += intent == .favorite ? 250 : 18 }
            if taste.likedMealIDs.contains(meal.id) { score += 15 }
            if taste.dislikedMealIDs.contains(meal.id) { score -= 40 }
            score += Double(taste.learnedScores[meal.id, default: 0]) * 3
            if taste.recentlyCookedMealIDs.contains(meal.id) { score -= 70 }
            if day == .friday || day == .saturday, meal.tags.contains(.weekend) { score += 15 }
            if day != .saturday && day != .sunday, meal.tags.contains(.quick) { score += 10 }
            score += Double(preferredRuleScore(meal: meal, day: day, rules: preferredRules, selected: selected))
            if intent == .quicker { score += Double(max(0, 90 - meal.prepMinutes)) }
            if intent == .cheaper { score += Double(max(0, 220 - meal.planningCost)) }
            return (meal, score)
        }
        return sample(from: scored)
    }

    /// Softmax sample. Shifts by the maximum score before exponentiating, so a wide score
    /// spread cannot overflow to infinity and collapse the distribution onto one candidate.
    private func sample(from scored: [(meal: Meal, score: Double)]) -> Meal? {
        guard !scored.isEmpty else { return nil }
        let highest = scored.map { $0.score }.max() ?? 0
        let weights = scored.map { exp(($0.score - highest) / Self.temperature) }
        let total = weights.reduce(0, +)
        guard total.isFinite, total > 0 else { return scored.max(by: { $0.score < $1.score })?.meal }

        var target = random.nextUniform() * total
        for (index, weight) in weights.enumerated() {
            target -= weight
            if target <= 0 { return scored[index].meal }
        }
        return scored.last?.meal
    }

    private func preferredRuleScore(meal: Meal, day: Weekday, rules: [PlanningRule], selected: [Weekday: Meal]) -> Int {
        var score = 0
        for rule in rules {
            switch rule.constraint {
            case .requiredOn(let ruleDay, let matcher) where ruleDay == day:
                score += matcher.matches(meal) ? 90 : 0
            case .excludedOn(let ruleDay, let matcher) where ruleDay == day:
                score += matcher.matches(meal) ? -90 : 0
            case .maximumPrepTime(let ruleDay, let minutes) where ruleDay == day:
                score += meal.prepMinutes <= minutes ? 50 : -50
            case .minimumPerWeek(let matcher, let minimum):
                let current = selected.values.filter(matcher.matches).count
                score += matcher.matches(meal) && current < minimum ? 35 : 0
            case .maximumPerWeek(let matcher, let maximum):
                let current = selected.values.filter(matcher.matches).count
                score += matcher.matches(meal) && current >= maximum ? -80 : 0
            default:
                continue
            }
        }
        return score
    }

    private func satisfyWeeklyMinimums(
        selected: inout [Weekday: Meal],
        entries: inout [Weekday: PlannedMeal],
        lockedDays: Set<Weekday>,
        preferredMeals: [Meal],
        allMeals: [Meal],
        rules: [PlanningRule],
        contexts: [Weekday: DayPlanContext]
    ) {
        for rule in rules {
            guard case .minimumPerWeek(let matcher, let minimum) = rule.constraint else { continue }
            while selected.values.filter(matcher.matches).count < minimum {
                let replacement = (preferredMeals + allMeals).first { meal in
                    matcher.matches(meal) && !exceedsMaximum(meal: meal, selected: selected, rules: rules)
                }
                guard let replacement else { break }
                let replacementDay = orderedDays.first { day in
                    guard !lockedDays.contains(day),
                          (contexts[day] ?? DayPlanContext()).mode == .cook,
                          let current = selected[day], !matcher.matches(current) else { return false }
                    return allows(meal: replacement, on: day, rules: rules)
                }
                guard let replacementDay else { break }
                selected[replacementDay] = replacement
                entries[replacementDay]?.mealID = replacement.id
            }
        }
    }

    private func validate(
        plan: WeeklyPlan,
        allMeals: [Meal],
        rules: [PlanningRule],
        contexts: [Weekday: DayPlanContext]
    ) -> [PlanConflict] {
        let byDay: [Weekday: Meal] = Dictionary(uniqueKeysWithValues: plan.meals.compactMap { item in
            guard let mealID = item.mealID else { return nil }
            return allMeals.first(where: { $0.id == mealID }).map { (item.day, $0) }
        })
        var conflicts: [PlanConflict] = []

        for day in orderedDays where plan[day] == nil {
            conflicts.append(PlanConflict(message: L10n.string("No plan was found for %@.", day.name.lowercased())))
        }

        for rule in rules {
            let ruleDescription = rule.summary(meals: allMeals)
            switch rule.constraint {
            case .requiredOn(let day, let matcher):
                if byDay[day].map(matcher.matches) != true {
                    conflicts.append(PlanConflict(
                        ruleID: rule.id,
                        message: L10n.string("“%@” cannot be satisfied on %@.", ruleDescription, day.name.lowercased()),
                        suggestion: (contexts[day] ?? DayPlanContext()).mode == .cook
                            ? L10n.string("Add a suitable meal or make the rule preferred.")
                            : L10n.string("Change the day plan or make the rule preferred.")
                    ))
                }
            case .excludedOn(let day, let matcher):
                if byDay[day].map(matcher.matches) == true {
                    conflicts.append(PlanConflict(
                        ruleID: rule.id,
                        message: L10n.string("“%@” is broken on %@.", ruleDescription, day.name.lowercased()),
                        suggestion: L10n.string("Unlock the day or make the rule preferred.")
                    ))
                }
            case .maximumPerWeek(let matcher, let count):
                let actual = byDay.values.filter(matcher.matches).count
                if actual > count {
                    conflicts.append(PlanConflict(
                        ruleID: rule.id,
                        message: L10n.string("“%@” allows %ld, but the plan needs %ld.", ruleDescription, count, actual),
                        suggestion: L10n.string("Raise the limit or replace a locked dinner.")
                    ))
                }
            case .minimumPerWeek(let matcher, let count):
                let actual = byDay.values.filter(matcher.matches).count
                if actual < count {
                    conflicts.append(PlanConflict(
                        ruleID: rule.id,
                        message: L10n.string("“%@” requires %ld, but only %ld are possible.", ruleDescription, count, actual),
                        suggestion: L10n.string("Add more suitable meals.")
                    ))
                }
            case .maximumPrepTime(let day, let minutes):
                if let meal = byDay[day], meal.prepMinutes > minutes {
                    conflicts.append(PlanConflict(
                        ruleID: rule.id,
                        message: L10n.string("“%@” is broken: %@ takes about %ld min.", ruleDescription, meal.name, meal.prepMinutes),
                        suggestion: L10n.string("Choose “Something quicker” for the dinner.")
                    ))
                }
            }
        }
        return conflicts
    }
}

enum GroceryListBuilder {
    static func build(plan: WeeklyPlan, meals: [Meal]) -> [GroceryItem] {
        struct Contribution {
            let name: String
            let quantity: Double
            let unit: String
            let aisle: GroceryAisle
            let mealName: String
            var key: String { "\(name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current))|\(unit)" }
        }

        let contributions: [Contribution] = plan.meals.flatMap { item in
            guard item.kind == .meal,
                  let mealID = item.mealID,
                  let meal = meals.first(where: { $0.id == mealID }) else { return [Contribution]() }
            let scale = Double(item.servings) / Double(max(meal.defaultServings, 1))
            return meal.ingredients.map { ingredient in
                let normalized = IngredientUnits.normalize(quantity: ingredient.quantity * scale, unit: ingredient.unit)
                return Contribution(name: ingredient.name, quantity: normalized.quantity, unit: normalized.unit, aisle: ingredient.aisle, mealName: meal.name)
            }
        }
        let grouped = Dictionary(grouping: contributions, by: \.key)

        return grouped.values.compactMap { matches in
            guard let first = matches.first else { return nil }
            return GroceryItem(
                name: first.name,
                quantity: matches.reduce(0) { $0 + $1.quantity },
                unit: first.unit,
                aisle: first.aisle,
                mealNames: Set(matches.map(\.mealName))
            )
        }.sorted {
            if $0.aisle != $1.aisle {
                return GroceryAisle.allCases.firstIndex(of: $0.aisle)! < GroceryAisle.allCases.firstIndex(of: $1.aisle)!
            }
            return $0.name < $1.name
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] { Array(Set(self)) }
}

private extension Array {
    func uniqued<Value: Hashable>(by keyPath: KeyPath<Element, Value>) -> [Element] {
        var seen = Set<Value>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
