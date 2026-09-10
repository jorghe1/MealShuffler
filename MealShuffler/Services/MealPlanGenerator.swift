import Foundation

/// Everything the generator knows about what this household likes.
///
/// Bundled so the signal set can grow (per-member preferences, seasonality) without the
/// generator's parameter list growing with it.
struct TasteProfile {
    var favoriteMealIDs: Set<UUID> = []
    var previousWeekDinner: Meal?
    var freezerBatches: [FreezerBatch] = []
    /// Swiped right during onboarding. A softer signal than an explicitly hearted favourite.
    var likedMealIDs: Set<UUID> = []
    /// Swiped left. Normally filtered out upstream, but still penalised here because the
    /// generator falls back to the full library when rules cannot otherwise be satisfied.
    var dislikedMealIDs: Set<UUID> = []
    var learnedScores: [UUID: Int] = [:]
    var recentlyCookedMealIDs: Set<UUID> = []
    /// Whole weeks since a meal was last on a plan, from the archive.
    ///
    /// What `noRepeatWithin` and `requiredEvery` are measured against. Absent means the meal
    /// has not been planned within the window the store looked back over.
    var weeksSinceLastPlanned: [UUID: Int] = [:]

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
        swapIntents: [Weekday: MealSwapIntent] = [:],
        matchContext: MealMatcher.MatchContext = .empty
    ) -> GenerationResult {
        let activeRules = rules.filter { $0.isActive(inWeek: existingPlan.startDate) }
        let requiredRules = activeRules.filter { $0.strength == .required }
        let preferredRules = activeRules.filter { $0.strength == .preferred }
        var selected: [Weekday: Meal] = [:]
        var entries: [Weekday: PlannedMeal] = [:]
        var conflicts: [PlanConflict] = []

        for item in existingPlan.meals where item.isLocked {
            entries[item.day] = item
            if item.kind == .meal, let mealID = item.mealID, let meal = allMeals.first(where: { $0.id == mealID }) {
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
                if let id = context.freezerBatchID {
                    let batch = taste.freezerBatches.first(where: { $0.id == id })
                    var item = PlannedMeal(day: day, mealID: batch?.recipe.id, isLocked: false, servings: context.diners, kind: .leftovers(sourceDay: day), portionScale: context.portionScale)
                    item.freezerBatch = batch; entries[day] = item; continue
                }
                if let source = resolveLeftoverSource(for: day, context: context, selected: selected),
                   let sourceMeal = selected[source] {
                    entries[day] = PlannedMeal(
                        day: day,
                        mealID: sourceMeal.id,
                        isLocked: false,
                        servings: context.diners,
                        kind: .leftovers(sourceDay: source),
                        portionScale: context.portionScale
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
                    entries[day] = PlannedMeal(day: day, mealID: nil, isLocked: false, servings: context.diners, kind: .leftovers(sourceDay: context.leftoverSourceDay ?? day), portionScale: context.portionScale)
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
            let previousDayMeal: Meal? = {
                guard let index = orderedDays.firstIndex(of: day), index > 0 else { return taste.previousWeekDinner }
                return selected[orderedDays[index - 1]]
            }()
            let preferred = candidatePool(
                for: day,
                from: preferredMeals,
                selected: selected,
                rules: requiredRules,
                dayContext: context,
                avoiding: avoidingMealOnDay[day],
                intent: intent,
                currentMeal: currentMeal,
                favoriteMealIDs: taste.favoriteMealIDs,
                enforceWeeklyMaximums: true,
                excludingUsed: true,
                previousDayMeal: previousDayMeal,
                taste: taste,
                context: matchContext
            )
            let fallback = candidatePool(
                for: day,
                from: allMeals,
                selected: selected,
                rules: requiredRules,
                dayContext: context,
                avoiding: avoidingMealOnDay[day],
                intent: intent,
                currentMeal: currentMeal,
                favoriteMealIDs: taste.favoriteMealIDs,
                enforceWeeklyMaximums: true,
                excludingUsed: true,
                previousDayMeal: previousDayMeal,
                taste: taste,
                context: matchContext
            )
            // Everything optional dropped: a small library or tight rules should degrade to
            // a repeat rather than to an unplanned day.
            let relaxed = candidates(
                for: day,
                from: allMeals,
                selected: selected,
                rules: requiredRules,
                dayContext: context,
                avoiding: nil,
                enforceWeeklyMaximums: true,
                previousDayMeal: previousDayMeal,
                taste: taste,
                context: matchContext
            )
            let pool = !preferred.isEmpty ? preferred : (!fallback.isEmpty ? fallback : relaxed)

            if let meal = chooseMeal(
                from: pool,
                day: day,
                selected: selected,
                preferredRules: preferredRules,
                taste: taste,
                intent: intent,
                matchContext: matchContext
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

        for day in orderedDays where entries[day]?.isLocked != true { entries[day]?.portionScale = contexts[day]?.portionScale }
        var plan = WeeklyPlan(startDate: existingPlan.startDate, meals: orderedDays.compactMap { entries[$0] })
        let initialIssues = validate(plan: plan, allMeals: allMeals, rules: requiredRules,
                                     contexts: contexts, taste: taste, context: matchContext)
        if !initialIssues.isEmpty {
            plan = searchPlan(allMeals: allMeals, rules: requiredRules, contexts: contexts, taste: taste,
                              existingPlan: existingPlan, fallback: plan, context: matchContext).anchored(to: existingPlan.startDate)
        }
        plan = resolvingLeftovers(in: plan, contexts: contexts, allMeals: allMeals, rules: requiredRules, matchContext: matchContext)
        conflicts = validate(
            plan: plan,
            allMeals: allMeals,
            rules: requiredRules,
            contexts: contexts,
            taste: taste,
            context: matchContext
        )

        // Not a rule violation: the plan is valid, it just had to reach past the meals this
        // household has expressed an opinion about. Marked informational so it stops being
        // counted and coloured as a broken rule.
        let preferredIDs = Set(preferredMeals.map(\.id))
        let fallbackNames = plan.meals.filter { $0.kind == .meal }.compactMap { item in allMeals.first { $0.id == item.mealID } }
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

    /// A bounded search repairs interacting rules without relaxing any required predicate.
    /// A partial safe plan is preferable to silently selecting a forbidden dinner.
    private func searchPlan(allMeals: [Meal], rules: [PlanningRule], contexts: [Weekday: DayPlanContext],
                            taste: TasteProfile, existingPlan: WeeklyPlan, fallback: WeeklyPlan,
                            context: MealMatcher.MatchContext) -> WeeklyPlan {
        var entries = Dictionary(uniqueKeysWithValues: existingPlan.meals.filter(\.isLocked).map { ($0.day, $0) })
        for day in orderedDays where entries[day] == nil && (contexts[day]?.mode ?? .cook) != .cook {
            entries[day] = fallback[day]
        }
        var selected = Dictionary(uniqueKeysWithValues: entries.values.compactMap { item -> (Weekday, Meal)? in
            guard item.kind == .meal, let meal = allMeals.first(where: { $0.id == item.mealID }) else { return nil }
            return (item.day, meal)
        })
        var best = Dictionary(uniqueKeysWithValues: fallback.meals.map { ($0.day, $0) })
        var attempts = 0
        var evaluations = 0
        let minimums = rules.compactMap { rule -> (matcher: MealMatcher, minimum: Int)? in
            guard case .minimumPerWeek(let matcher, let count) = rule.constraint else { return nil }
            return (matcher, count)
        } + overdueMinimums(rules: rules, taste: taste, context: context, allMeals: allMeals)
        let priorities = Dictionary(uniqueKeysWithValues: allMeals.map { ($0.id, random.nextUniform()) })
        func visit(_ remaining: [Weekday]) -> Bool {
            attempts += 1
            guard !Task.isCancelled, attempts <= 20_000, evaluations <= 250_000 else { return false }
            if entries.count > best.count { best = entries }
            if remaining.isEmpty {
                let candidate = resolvingLeftovers(in: WeeklyPlan(startDate: existingPlan.startDate, meals: orderedDays.compactMap { entries[$0] }), contexts: contexts,
                    allMeals: allMeals, rules: rules, matchContext: context)
                let valid = validate(plan: candidate, allMeals: allMeals, rules: rules, contexts: contexts,
                                taste: taste, context: context).isEmpty
                if valid { entries = Dictionary(uniqueKeysWithValues: candidate.meals.map { ($0.day, $0) }) }
                return valid
            }
            let options = remaining.map { day -> (Weekday, [Meal]) in
                evaluations += allMeals.count
                let pool = candidates(for: day, from: allMeals, selected: selected, rules: rules,
                    dayContext: contexts[day] ?? DayPlanContext(), avoiding: nil, enforceWeeklyMaximums: true,
                    previousDayMeal: nil, taste: taste, context: context)
                return (day, pool.sorted { left, right in
                    let leftUsed = selected.values.contains { $0.id == left.id }
                    let rightUsed = selected.values.contains { $0.id == right.id }
                    if leftUsed != rightUsed { return !leftUsed }
                    return priorities[left.id, default: 0] < priorities[right.id, default: 0]
                })
            }
            for requirement in minimums {
                let actual = selected.values.filter { requirement.matcher.matches($0, context: context) }.count
                let possible = options.filter { option in
                    option.1.contains { requirement.matcher.matches($0, context: context.forDay(option.0)) }
                }.count
                if actual + possible < requirement.minimum { return false }
            }
            guard let (day, pool) = options.min(by: { $0.1.count < $1.1.count }), !pool.isEmpty else { return false }
            for meal in pool {
                selected[day] = meal
                entries[day] = PlannedMeal(day: day, mealID: meal.id, isLocked: false,
                                          servings: (contexts[day] ?? DayPlanContext()).cookedServings, portionScale: contexts[day]?.portionScale)
                if visit(remaining.filter { $0 != day }) { return true }
                selected.removeValue(forKey: day)
                entries.removeValue(forKey: day)
                if attempts > 20_000 || evaluations > 250_000 { break }
            }
            return false
        }
        let remaining = orderedDays.filter { entries[$0] == nil }
        if visit(remaining) { return WeeklyPlan(meals: orderedDays.compactMap { entries[$0] }) }
        return WeeklyPlan(meals: orderedDays.compactMap { best[$0] })
    }

    func resolvingLeftovers(in plan: WeeklyPlan, contexts: [Weekday: DayPlanContext], allMeals: [Meal] = [], rules: [PlanningRule] = [], matchContext: MealMatcher.MatchContext = .empty) -> WeeklyPlan {
        var result = plan
        var allocated: [Weekday: Double] = [:]
        for day in orderedDays {
            guard var item = result[day], item.freezerBatch == nil, contexts[day]?.freezerBatchID == nil, case .leftovers(let oldSource) = item.kind,
                  let index = orderedDays.firstIndex(of: day) else { continue }
            let earlier = Array(orderedDays[..<index].reversed())
            func usable(_ source: Weekday) -> Bool {
                guard earlier.contains(source), let origin = result[source], origin.kind == .meal, let id = origin.mealID else { return false }
                let available = origin.effectiveServings - (contexts[source]?.effectiveDiners ?? 4) - allocated[source, default: 0]
                guard available >= item.effectiveServings else { return false }
                if let meal = allMeals.first(where: { $0.id == id }) {
                    return !rules.contains { rule in
                        guard rule.strength == .required, rule.isActive(inWeek: plan.startDate), case .excludedOn(let scope, let matcher) = rule.constraint else { return false }
                        return scope.covers(day) && matcher.matches(meal, context: matchContext.forDay(day))
                    }
                }
                return true
            }
            let source = contexts[day]?.leftoverSourceDay ?? earlier.first(where: usable) ?? oldSource
            item.kind = .leftovers(sourceDay: source)
            if earlier.contains(source),
               let origin = result[source], origin.kind == .meal {
                item.mealID = origin.mealID
            } else { item.mealID = nil }
            allocated[source, default: 0] += item.effectiveServings
            result[day] = item
        }
        return result
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
        dayContext: DayPlanContext,
        avoiding: UUID?,
        intent: MealSwapIntent?,
        currentMeal: Meal?,
        favoriteMealIDs: Set<UUID>,
        enforceWeeklyMaximums: Bool,
        excludingUsed: Bool = false,
        previousDayMeal: Meal?,
        taste: TasteProfile,
        context: MealMatcher.MatchContext
    ) -> [Meal] {
        let base = candidates(
            for: day,
            from: meals,
            selected: selected,
            rules: rules,
            dayContext: dayContext,
            avoiding: avoiding,
            enforceWeeklyMaximums: enforceWeeklyMaximums,
            excludingUsed: excludingUsed,
            previousDayMeal: previousDayMeal,
            taste: taste,
            context: context
        )
        guard let intent else { return base }

        let refined: [Meal]
        switch intent {
        case .different, .surprise:
            refined = base
        case .quicker:
            refined = currentMeal.map { current in base.filter { $0.prepMinutes < current.prepMinutes } } ?? base
        case .cheaper:
            refined = currentMeal.map { current in base.filter { $0.costPerServing < current.costPerServing } } ?? base
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
        dayContext: DayPlanContext,
        avoiding: UUID?,
        enforceWeeklyMaximums: Bool,
        /// Serving the same dinner twice in one week is a constraint, not a preference.
        /// Expressing it as a score bonus made it merely improbable -- roughly one week in
        /// thirteen still repeated. The relaxed pool leaves it off, so a small library or
        /// tight rules degrade to a repeat rather than to no plan at all.
        excludingUsed: Bool = false,
        previousDayMeal: Meal?,
        taste: TasteProfile,
        context: MealMatcher.MatchContext
    ) -> [Meal] {
        let usedIDs = excludingUsed ? Set(selected.values.map(\.id)) : []
        return meals.filter { meal in
            if meal.id == avoiding { return false }
            if usedIDs.contains(meal.id) { return false }
            if let maximum = dayContext.maximumPrepMinutes, meal.prepMinutes <= 0 || meal.prepMinutes > maximum { return false }
            guard allows(meal: meal, on: day, rules: rules, context: context) else { return false }
            if exceedsMaximum(meal: meal, selected: selected, rules: rules, context: context) { return false }
            if repeatsTooSoon(meal: meal, rules: rules, taste: taste) { return false }
            if rules.contains(where: { if case .noRepeatWithin = $0.constraint { return true }; return false }),
               selected.values.contains(where: { $0.id == meal.id }) { return false }
            if let index = orderedDays.firstIndex(of: day) {
                for neighbor in [index - 1, index + 1] where orderedDays.indices.contains(neighbor) {
                    if follows(selected[orderedDays[neighbor]], meal: meal, rules: rules, context: context) { return false }
                }
            }
            if day == orderedDays.first, follows(taste.previousWeekDinner, meal: meal, rules: rules, context: context) { return false }
            return !follows(previousDayMeal, meal: meal, rules: rules, context: context)
        }
    }

    private func allows(
        meal: Meal,
        on day: Weekday,
        rules: [PlanningRule],
        context: MealMatcher.MatchContext
    ) -> Bool {
        let dayContext = context.forDay(day)
        for rule in rules {
            switch rule.constraint {
            case .requiredOn(let scope, let matcher) where scope.covers(day):
                if !matcher.matches(meal, context: dayContext) { return false }
            case .excludedOn(let scope, let matcher) where scope.covers(day):
                if matcher.matches(meal, context: dayContext) { return false }
            case .maximumPrepTime(let scope, let minutes) where scope.covers(day):
                if meal.prepMinutes <= 0 || meal.prepMinutes > minutes { return false }
            default:
                continue
            }
        }
        return true
    }

    private func exceedsMaximum(
        meal: Meal,
        selected: [Weekday: Meal],
        rules: [PlanningRule],
        context: MealMatcher.MatchContext
    ) -> Bool {
        for rule in rules {
            guard case .maximumPerWeek(let matcher, let maximum) = rule.constraint,
                  matcher.matches(meal, context: context) else { continue }
            if selected.values.filter({ matcher.matches($0, context: context) }).count >= maximum { return true }
        }
        return false
    }

    /// True when a rule says this meal has been served too recently to come round again.
    ///
    /// A window of one week is what the no-repeat pool already enforces, so only longer
    /// windows reach past the current week into the archive.
    private func repeatsTooSoon(meal: Meal, rules: [PlanningRule], taste: TasteProfile) -> Bool {
        for rule in rules {
            guard case .noRepeatWithin(let weeks) = rule.constraint, weeks > 1 else { continue }
            guard let weeksAgo = taste.weeksSinceLastPlanned[meal.id] else { continue }
            if weeksAgo < weeks { return true }
        }
        return false
    }

    /// True when putting this meal here would break a "not two days running" rule.
    private func follows(
        _ previous: Meal?,
        meal: Meal,
        rules: [PlanningRule],
        context: MealMatcher.MatchContext
    ) -> Bool {
        guard let previous else { return false }
        for rule in rules {
            guard case .notOnConsecutiveDays(let matcher) = rule.constraint else { continue }
            if matcher.matches(meal, context: context), matcher.matches(previous, context: context) {
                return true
            }
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
        intent: MealSwapIntent?,
        matchContext: MealMatcher.MatchContext
    ) -> Meal? {
        guard !meals.isEmpty else { return nil }
        guard meals.count > 1 else { return meals.first }
        let usedIDs = Set(selected.values.map(\.id))
        let previousMeal: Meal? = {
            guard let index = orderedDays.firstIndex(of: day), index > 0 else { return taste.previousWeekDinner }
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
            score += Double(preferredRuleScore(
                meal: meal,
                day: day,
                rules: preferredRules,
                selected: selected,
                previousDayMeal: previousMeal,
                taste: taste,
                context: matchContext
            ))
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

    private func preferredRuleScore(
        meal: Meal,
        day: Weekday,
        rules: [PlanningRule],
        selected: [Weekday: Meal],
        previousDayMeal: Meal?,
        taste: TasteProfile,
        context: MealMatcher.MatchContext
    ) -> Int {
        var score = 0
        for rule in rules {
            switch rule.constraint {
            case .requiredOn(let scope, let matcher) where scope.covers(day):
                score += matcher.matches(meal, context: context) ? 90 : 0
            case .excludedOn(let scope, let matcher) where scope.covers(day):
                score += matcher.matches(meal, context: context) ? -90 : 0
            case .maximumPrepTime(let scope, let minutes) where scope.covers(day):
                score += meal.prepMinutes <= minutes ? 50 : -50
            case .minimumPerWeek(let matcher, let minimum):
                let current = selected.values.filter { matcher.matches($0, context: context) }.count
                score += matcher.matches(meal, context: context) && current < minimum ? 35 : 0
            case .maximumPerWeek(let matcher, let maximum):
                let current = selected.values.filter { matcher.matches($0, context: context) }.count
                score += matcher.matches(meal, context: context) && current >= maximum ? -80 : 0
            case .noRepeatWithin(let weeks) where weeks > 1:
                if let weeksAgo = taste.weeksSinceLastPlanned[meal.id], weeksAgo < weeks {
                    score -= 80
                }
            case .requiredEvery(_, let matcher):
                // Required recurrence is checked for the whole week; here it is
                // only a nudge towards the meals that would settle it.
                score += matcher.matches(meal, context: context) ? 30 : 0
            case .notOnConsecutiveDays(let matcher):
                if let previousDayMeal,
                   matcher.matches(meal, context: context),
                   matcher.matches(previousDayMeal, context: context) {
                    score -= 80
                }
            default:
                continue
            }
        }
        return score
    }

    /// Meals a `requiredEvery` rule says are overdue, folded in as a minimum of one.
    private func overdueMinimums(
        rules: [PlanningRule],
        taste: TasteProfile,
        context: MealMatcher.MatchContext,
        allMeals: [Meal]
    ) -> [(matcher: MealMatcher, minimum: Int)] {
        rules.compactMap { rule in
            guard case .requiredEvery(let weeks, let matcher) = rule.constraint else { return nil }
            let matching = allMeals.filter { matcher.matches($0, context: context) }
            guard !matching.isEmpty else { return nil }
            // Nothing that matches has been planned inside the window, so it is due.
            let seenRecently = matching.contains { meal in
                (taste.weeksSinceLastPlanned[meal.id] ?? Int.max) < weeks
            }
            return seenRecently ? nil : (matcher, 1)
        }
    }

    func validate(
        plan: WeeklyPlan,
        allMeals: [Meal],
        rules: [PlanningRule],
        contexts: [Weekday: DayPlanContext],
        taste: TasteProfile,
        context: MealMatcher.MatchContext
    ) -> [PlanConflict] {
        let servedByDay: [Weekday: Meal] = Dictionary(uniqueKeysWithValues: plan.meals.compactMap { item in
            guard let id = item.mealID else { return nil }
            return (item.freezerBatch?.recipe ?? allMeals.first(where: { $0.id == id })).map { (item.day, $0) }
        })
        let byDay: [Weekday: Meal] = Dictionary(uniqueKeysWithValues: plan.meals.compactMap { item in
            guard let mealID = item.mealID, item.kind == .meal else { return nil }
            return allMeals.first(where: { $0.id == mealID }).map { (item.day, $0) }
        })
        var conflicts: [PlanConflict] = []

        for day in orderedDays where plan[day] == nil || (plan[day]?.kind == .meal && byDay[day] == nil) {
            conflicts.append(PlanConflict(message: L10n.string("No plan was found for %@.", day.name.lowercased())))
        }

        /// Days a scope covers that the household is cooking on.
        ///
        /// Decided by the day's plan, never by whether a meal landed on it. Those are two
        /// different days: one the household set aside -- away, takeaway, leftovers -- where
        /// a dinner rule does not apply, and one the generator could not fill, which is very
        /// often the rule's own doing and has to say so. Asking "did a meal land here" made
        /// them the same, and an unfillable day lost the name of the rule that emptied it.
        func cookingDays(in scope: DayScope) -> [Weekday] {
            orderedDays.filter { scope.covers($0) && (contexts[$0] ?? DayPlanContext()).mode == .cook }
        }

        for rule in rules where rule.isActive(inWeek: plan.startDate) && rule.strength == .required {
            let ruleDescription = rule.summary(meals: allMeals, context: context)
            switch rule.constraint {
            case .requiredOn(let scope, let matcher):
                for day in cookingDays(in: scope)
                where byDay[day].map({ matcher.matches($0, context: context.forDay(day)) }) != true {
                    conflicts.append(PlanConflict(
                        ruleID: rule.id,
                        message: L10n.string("“%@” cannot be satisfied on %@.", ruleDescription, day.name.lowercased()),
                        suggestion: L10n.string("Add a suitable meal or make the rule preferred.")
                    ))
                }
            case .excludedOn(let scope, let matcher):
                for day in orderedDays where scope.covers(day)
                    && servedByDay[day].map({ matcher.matches($0, context: context.forDay(day)) }) == true {
                    conflicts.append(PlanConflict(
                        ruleID: rule.id,
                        message: L10n.string("“%@” is broken on %@.", ruleDescription, day.name.lowercased()),
                        suggestion: L10n.string("Unlock the day or make the rule preferred.")
                    ))
                }
            case .maximumPerWeek(let matcher, let count):
                let actual = byDay.values.filter { matcher.matches($0, context: context) }.count
                if actual > count {
                    conflicts.append(PlanConflict(
                        ruleID: rule.id,
                        message: L10n.string("“%@” allows %ld, but the plan needs %ld.", ruleDescription, count, actual),
                        suggestion: L10n.string("Raise the limit or replace a locked dinner.")
                    ))
                }
            case .minimumPerWeek(let matcher, let count):
                let actual = byDay.values.filter { matcher.matches($0, context: context) }.count
                if actual < count {
                    conflicts.append(PlanConflict(
                        ruleID: rule.id,
                        message: L10n.string("“%@” requires %ld, but this plan contains %ld.", ruleDescription, count, actual),
                        suggestion: L10n.string("Add more suitable meals.")
                    ))
                }
            case .maximumPrepTime(let scope, let minutes):
                for day in cookingDays(in: scope) {
                    guard let meal = byDay[day], meal.prepMinutes > minutes else { continue }
                    conflicts.append(PlanConflict(
                        ruleID: rule.id,
                        message: L10n.string("“%@” is broken: %@ takes about %ld min.", ruleDescription, meal.name, meal.prepMinutes),
                        suggestion: L10n.string("Choose “Something quicker” for the dinner.")
                    ))
                }
            case .requiredEvery(let weeks, let matcher):
                let matching = allMeals.filter { matcher.matches($0, context: context) }
                let seenRecently = matching.contains { (taste.weeksSinceLastPlanned[$0.id] ?? Int.max) < weeks }
                let onThisPlan = byDay.values.contains { matcher.matches($0, context: context) }
                if !seenRecently && !onThisPlan {
                    conflicts.append(PlanConflict(
                        ruleID: rule.id,
                        message: L10n.string("“%@” is overdue and could not be fitted in.", ruleDescription),
                        suggestion: L10n.string("Free up a day, or make the rule preferred.")
                    ))
                }
            case .notOnConsecutiveDays(let matcher):
                if let first = orderedDays.first, let current = byDay[first], let previous = taste.previousWeekDinner,
                   matcher.matches(current, context: context.forDay(first)), matcher.matches(previous, context: context) {
                    conflicts.append(PlanConflict(ruleID: rule.id,
                        message: L10n.string("“%@” conflicts with the last dinner of the previous week.", ruleDescription),
                        suggestion: L10n.string("Choose another dinner for the first day.")))
                }
                for index in orderedDays.indices where index > 0 {
                    guard let current = byDay[orderedDays[index]], let previous = byDay[orderedDays[index - 1]],
                          matcher.matches(current, context: context),
                          matcher.matches(previous, context: context) else { continue }
                    conflicts.append(PlanConflict(
                        ruleID: rule.id,
                        message: L10n.string(
                            "“%@” is broken: %@ and %@ are back to back.",
                            ruleDescription, orderedDays[index - 1].name.lowercased(), orderedDays[index].name.lowercased()
                        ),
                        suggestion: L10n.string("Swap one of the two days.")
                    ))
                }
            case .noRepeatWithin:
                let ids = byDay.values.map(\.id)
                if Set(ids).count != ids.count || byDay.values.contains(where: { repeatsTooSoon(meal: $0, rules: [rule], taste: taste) }) {
                    conflicts.append(PlanConflict(ruleID: rule.id, message: ruleDescription,
                        suggestion: L10n.string("Add a suitable meal or make the rule preferred.")))
                }
            case .dinnerMode(let scope, let mode):
                for day in scope.days() {
                    if contexts[day]?.overridesDinnerMode == true { continue }
                    guard let item = plan[day] else { continue }
                    let actual: DayDinnerMode
                    switch item.kind { case .meal: actual = .cook; case .away: actual = .away
                    case .takeaway: actual = .takeaway; case .leftovers: actual = .leftovers }
                    if actual != mode { conflicts.append(PlanConflict(ruleID: rule.id, message: ruleDescription)) }
                }
            }
        }
        var allocated: [Weekday: Double] = [:]
        var frozenAllocations: [UUID: Double] = [:]
        for day in orderedDays {
            guard let item = plan[day] else { continue }
            if let limit = contexts[day]?.maximumPrepMinutes, let meal = byDay[day], meal.prepMinutes > limit {
                conflicts.append(PlanConflict(message: L10n.string("%@ exceeds the time available on %@.", meal.name, day.name)))
            }
            if let batch = item.freezerBatch {
                if item.freezerConsumed == true { continue }
                frozenAllocations[batch.id, default: 0] += item.effectiveServings
                let available = taste.freezerBatches.first(where: { $0.id == batch.id })?.portions ?? 0
                if frozenAllocations[batch.id, default: 0] > available {
                    conflicts.append(PlanConflict(message: L10n.string("Not enough freezer portions for %@.", day.name), suggestion: L10n.string("Choose another batch or reduce the portions.")))
                }
                continue
            }
            if contexts[day]?.freezerBatchID != nil, item.freezerBatch == nil {
                conflicts.append(PlanConflict(message: L10n.string("The freezer batch for %@ is no longer available.", day.name), suggestion: L10n.string("Choose another batch or reduce the portions.")))
                continue
            }
            if case .leftovers(let source) = item.kind {
                allocated[source, default: 0] += item.effectiveServings
                let available = max(0, (plan[source]?.effectiveServings ?? 0) - (contexts[source] ?? DayPlanContext()).effectiveDiners)
                if item.mealID == nil || allocated[source, default: 0] > available {
                    conflicts.append(PlanConflict(message: L10n.string("Not enough leftovers for %@.", day.name),
                        suggestion: L10n.string("Increase the number of extra servings on %@.", source.name.lowercased())))
                }
            }
        }
        return conflicts
    }
}

enum GroceryListBuilder {
    static func build(
        plan: WeeklyPlan,
        meals: [Meal],
        manualItems: [ManualGroceryItem] = []
    ) -> [GroceryItem] {
        struct Contribution {
            let name: String
            let quantity: Double
            let unit: String
            let aisle: GroceryAisle
            let mealName: String
            var amountNote: String?
            var key: String { IngredientUnits.key(name: name, unit: unit) }
        }

        let contributions: [Contribution] = plan.meals.flatMap { item in
            guard item.kind == .meal,
                  let mealID = item.mealID,
                  let meal = meals.first(where: { $0.id == mealID }) else { return [Contribution]() }
            let scale = item.effectiveServings / Double(max(meal.defaultServings, 1))
            return meal.ingredients.map { ingredient in
                let amount = (ingredient.upperQuantity ?? ingredient.quantity) * (ingredient.packageQuantity ?? 1)
                let normalized = IngredientUnits.normalize(quantity: amount * scale, unit: ingredient.packageUnit ?? ingredient.unit)
                return Contribution(name: ingredient.name, quantity: normalized.quantity, unit: normalized.unit, aisle: ingredient.aisle, mealName: meal.name, amountNote: ingredient.amountNote)
            }
        }
        let grouped = Dictionary(grouping: contributions, by: \.key)

        var items = grouped.values.compactMap { matches -> GroceryItem? in
            guard let first = matches.first else { return nil }
            return GroceryItem(
                name: first.name,
                quantity: matches.reduce(0) { $0 + $1.quantity },
                unit: first.unit,
                aisle: first.aisle,
                mealNames: Set(matches.map(\.mealName)),
                hasUnspecifiedAmount: matches.contains { $0.quantity <= 0 },
                amountNote: matches.contains { $0.quantity <= 0 && $0.amountNote == nil } ? nil : Array(Set(matches.compactMap(\.amountNote))).sorted().joined(separator: ", ")
            )
        }

        // A manual entry that names something the plan already needs adds to it rather
        // than sitting as a duplicate line.
        for manual in manualItems {
            let normalized = IngredientUnits.normalize(quantity: manual.quantity ?? 0, unit: manual.unit)
            if let index = items.firstIndex(where: { $0.id == manual.groceryID }) {
                let existing = items[index]
                items[index] = GroceryItem(
                    name: existing.name,
                    quantity: existing.quantity + normalized.quantity,
                    unit: existing.unit,
                    aisle: existing.aisle,
                    mealNames: existing.mealNames,
                    isManual: existing.isManual,
                    hasUnspecifiedAmount: existing.hasUnspecifiedAmount || manual.quantity == nil,
                    amountNote: manual.quantity == nil ? nil : existing.amountNote
                )
            } else {
                items.append(GroceryItem(
                    name: manual.name,
                    quantity: normalized.quantity,
                    unit: normalized.unit,
                    aisle: manual.aisle,
                    mealNames: [],
                    isManual: true
                ))
            }
        }

        return items.sorted {
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
