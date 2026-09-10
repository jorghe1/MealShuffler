import SwiftUI

/// What kind of week this is, in one bar.
///
/// The app's whole premise is variety under constraints, and nothing in it ever showed the
/// result. This is the rules engine made visible: it answers "is this week balanced" without
/// reading seven cards, and it is where an unbalanced week becomes obvious enough to fix.
struct WeekCompositionView: View {
    let plan: WeeklyPlan
    let meals: [Meal]

    /// The coarse kind of food a meal is. First match wins, so a chicken pasta counts as
    /// chicken -- the protein is what a household is actually varying.
    enum Category: String, CaseIterable, Identifiable {
        case fish, chicken, meat, vegetarian, other

        var id: String { rawValue }

        var name: String {
            switch self {
            case .fish: L10n.string("Fish")
            case .chicken: L10n.string("Chicken")
            case .meat: L10n.string("Meat")
            case .vegetarian: L10n.string("Vegetarian")
            case .other: L10n.string("Other")
            }
        }

        var color: Color {
            switch self {
            case .fish: AppTheme.categoryFish
            case .chicken: AppTheme.categoryChicken
            case .meat: AppTheme.categoryMeat
            case .vegetarian: AppTheme.categoryVegetarian
            case .other: AppTheme.categoryOther
            }
        }

        static func of(_ meal: Meal) -> Category {
            if meal.tags.contains(.fish) { return .fish }
            if meal.tags.contains(.chicken) { return .chicken }
            if meal.tags.contains(.meat) { return .meat }
            if meal.tags.contains(.vegetarian) { return .vegetarian }
            return .other
        }
    }

    /// Only days that are actually cooked. Leftovers repeat a dinner that is already
    /// counted, and away and takeaway days are not food this household is choosing.
    private var counts: [(category: Category, count: Int)] {
        var tally: [Category: Int] = [:]
        for item in plan.meals where item.kind == .meal {
            guard let mealID = item.mealID,
                  let meal = meals.first(where: { $0.id == mealID }) else { continue }
            tally[Category.of(meal), default: 0] += 1
        }
        return Category.allCases.compactMap { category in
            guard let count = tally[category], count > 0 else { return nil }
            return (category, count)
        }
    }

    private var total: Int { counts.reduce(0) { $0 + $1.count } }

    private var summary: String {
        counts
            .map { L10n.string("%ld %@", $0.count, $0.category.name.lowercased()) }
            .joined(separator: ", ")
    }

    var body: some View {
        if total > 0 {
            VStack(alignment: .leading, spacing: 9) {
                GeometryReader { proxy in
                    HStack(spacing: 3) {
                        ForEach(counts, id: \.category) { entry in
                            Capsule()
                                .fill(entry.category.color)
                                .frame(width: width(for: entry.count, in: proxy.size.width))
                        }
                    }
                }
                .frame(height: 10)

                // A colour-only chart is unreadable for a good share of people; the legend
                // carries the same information as text.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(counts, id: \.category) { entry in
                        HStack(spacing: 5) {
                            Circle().fill(entry.category.color).frame(width: 8, height: 8)
                            Text("\(entry.count)")
                                .font(.caption.weight(.bold)).foregroundStyle(AppTheme.ink)
                            Text(entry.category.name)
                                .font(.caption).foregroundStyle(AppTheme.muted)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.string("This week: %@", summary))
        }
    }

    private func width(for count: Int, in available: CGFloat) -> CGFloat {
        guard total > 0, available > 0 else { return 0 }
        let gaps = CGFloat(max(counts.count - 1, 0)) * 3
        return max((available - gaps) * CGFloat(count) / CGFloat(total), 4)
    }
}
