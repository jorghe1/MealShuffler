import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAddRule = false
    @State private var showingResetConfirmation = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rules written as plain sentences")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text("Required rules must be followed. Preferred rules influence the choice, but never block an otherwise good week.")
                        .font(.subheadline).foregroundStyle(AppTheme.muted).lineSpacing(3)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Your rules") {
                ForEach(store.rules) { rule in
                    HStack(spacing: 12) {
                        Image(systemName: symbol(for: rule.constraint))
                            .foregroundStyle(rule.isEnabled ? AppTheme.accent : AppTheme.muted)
                            .frame(width: 36, height: 36)
                            .background(rule.isEnabled ? AppTheme.accentSoft : Color.gray.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(rule.summary(meals: store.meals)).font(.headline).foregroundStyle(AppTheme.ink)
                            Menu {
                                Button("Required") { store.setRuleStrength(.required, ruleID: rule.id) }
                                Button("Preferred") { store.setRuleStrength(.preferred, ruleID: rule.id) }
                            } label: {
                                Label(rule.strength.name, systemImage: rule.strength == .required ? "exclamationmark.shield.fill" : "sparkles")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(rule.strength == .required ? AppTheme.warning : AppTheme.accent)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { store.rules.first(where: { $0.id == rule.id })?.isEnabled ?? false },
                            set: { _ in store.toggleRule(rule) }
                        )).labelsHidden()
                    }
                    .padding(.vertical, 5)
                }
                .onDelete(perform: store.deleteRules)
            }

            Section {
                Button { showingAddRule = true } label: {
                    Label("Create a new rule", systemImage: "plus.circle.fill").font(.headline)
                }
            }

            Section("Settings") {
                NavigationLink { HouseholdView() } label: {
                    Label("Family and sharing", systemImage: "person.2")
                }
                Button("Show onboarding again") { showingResetConfirmation = true }
                    .foregroundStyle(AppTheme.warning)
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Rules")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddRule) { AddRuleView().environmentObject(store) }
        .confirmationDialog("Start onboarding again?", isPresented: $showingResetConfirmation) {
            Button("Start over", role: .destructive) { store.resetForPreview() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Rules and custom meals are kept, but taste choices and the weekly plan are reset.") }
    }

    private func symbol(for constraint: RuleConstraint) -> String {
        switch constraint {
        case .requiredOn: "calendar.badge.checkmark"
        case .excludedOn: "calendar.badge.minus"
        case .maximumPerWeek: "lessthan.circle"
        case .minimumPerWeek: "greaterthan.circle"
        case .maximumPrepTime: "clock"
        }
    }
}

private struct AddRuleView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode: RuleMode = .requiredDay
    @State private var weekday: Weekday = .monday
    @State private var targetKind: TargetKind = .category
    @State private var tag: MealTag = .fish
    @State private var mealID: UUID = SampleMeals.all[0].id
    @State private var count = 1
    @State private var minutes = 30
    @State private var strength: RuleStrength = .required

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("What should the rule do?")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                        Text("Choose a template and tap the green words to change the sentence.")
                            .foregroundStyle(AppTheme.muted)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RuleMode.allCases) { option in
                                Button { withAnimation(.snappy) { mode = option } } label: {
                                    Label(option.shortName, systemImage: option.symbol)
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 12).padding(.vertical, 10)
                                        .background(mode == option ? AppTheme.accent : .white)
                                        .foregroundStyle(mode == option ? .white : AppTheme.ink)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    sentenceCard

                    VStack(alignment: .leading, spacing: 10) {
                        Text("How strict?").font(.headline)
                        Picker("Strength", selection: $strength) {
                            ForEach(RuleStrength.allCases) { item in Text(item.name).tag(item) }
                        }
                        .pickerStyle(.segmented)
                        Text(strength == .required
                             ? "The plan shows a conflict if the rule cannot be followed."
                             : "The rule gets higher priority, but can yield to required rules.")
                            .font(.caption).foregroundStyle(AppTheme.muted)
                    }
                    .padding(18).mealCard()

                    Label(
                        L10n.string("%ld of %ld meals work with this choice", matchingMealCount, store.meals.count),
                        systemImage: "checkmark.circle.fill"
                    )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(matchingMealCount == 0 ? AppTheme.warning : AppTheme.accent)

                    Button {
                        store.addRule(previewRule)
                        dismiss()
                    } label: {
                        Text("Add rule").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 18))
                    .disabled(matchingMealCount == 0 && mode != .excludedDay)
                }
                .padding(20)
            }
            .appBackground()
            .navigationTitle("New rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var sentenceCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("RULE").font(.caption.bold()).tracking(1).foregroundStyle(AppTheme.accent)
            Group {
                switch mode {
                case .requiredDay:
                    HStack(spacing: 7) { Text("On"); dayMenu; Text("we'll have") }
                    targetMenu
                case .excludedDay:
                    HStack(spacing: 7) { Text("On"); dayMenu; Text("we won't have") }
                    targetMenu
                case .maximumPerWeek:
                    HStack(spacing: 7) { Text("Maximum"); countMenu; targetMenu; Text("per week") }
                case .minimumPerWeek:
                    HStack(spacing: 7) { Text("At least"); countMenu; targetMenu; Text("per week") }
                case .maximumPrepTime:
                    HStack(spacing: 7) { Text("On"); dayMenu; Text("dinner should take") }
                    HStack(spacing: 7) { Text("at most"); minuteMenu }
                }
            }
            .font(.title3.weight(.semibold))

            if mode.usesMatcher {
                Picker("Target", selection: $targetKind) {
                    ForEach(TargetKind.allCases) { Text($0.name).tag($0) }
                }.pickerStyle(.segmented)
            }
        }
        .padding(20).mealCard()
    }

    private var dayMenu: some View {
        Menu { ForEach(Weekday.allCases) { day in Button(day.name) { weekday = day } } } label: {
            SentenceToken(text: weekday.name)
        }
    }

    private var targetMenu: some View {
        Menu {
            if targetKind == .category {
                ForEach(MealTag.allCases) { item in Button(item.name) { tag = item } }
            } else {
                ForEach(store.meals) { meal in Button("\(meal.emoji) \(meal.name)") { mealID = meal.id } }
            }
        } label: { SentenceToken(text: matcher.label(meals: store.meals).lowercased()) }
    }

    private var countMenu: some View {
        Menu { ForEach(1...7, id: \.self) { value in Button("\(value)") { count = value } } } label: {
            SentenceToken(text: "\(count)")
        }
    }

    private var minuteMenu: some View {
        Menu { ForEach(Array(stride(from: 15, through: 120, by: 5)), id: \.self) { value in Button("\(value) min") { minutes = value } } } label: {
            SentenceToken(text: L10n.string("%ld minutes", minutes))
        }
    }

    private var matcher: MealMatcher { targetKind == .category ? .tag(tag) : .exactMeal(mealID) }

    private var previewRule: PlanningRule {
        let constraint: RuleConstraint
        switch mode {
        case .requiredDay: constraint = .requiredOn(day: weekday, matcher: matcher)
        case .excludedDay: constraint = .excludedOn(day: weekday, matcher: matcher)
        case .maximumPerWeek: constraint = .maximumPerWeek(matcher: matcher, count: count)
        case .minimumPerWeek: constraint = .minimumPerWeek(matcher: matcher, count: count)
        case .maximumPrepTime: constraint = .maximumPrepTime(day: weekday, minutes: minutes)
        }
        return PlanningRule(title: mode.generatedTitle(matcher: matcher, meals: store.meals), strength: strength, constraint: constraint)
    }

    private var matchingMealCount: Int {
        switch previewRule.constraint {
        case .maximumPrepTime(_, let minutes): store.meals.filter { $0.prepMinutes <= minutes }.count
        case .requiredOn(_, let matcher), .minimumPerWeek(let matcher, _), .maximumPerWeek(let matcher, _):
            store.meals.filter(matcher.matches).count
        case .excludedOn(_, let matcher): store.meals.filter { !matcher.matches($0) }.count
        }
    }
}

private struct SentenceToken: View {
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(AppTheme.accentSoft)
        .foregroundStyle(AppTheme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private enum RuleMode: String, CaseIterable, Identifiable {
    case requiredDay, excludedDay, maximumPerWeek, minimumPerWeek, maximumPrepTime
    var id: String { rawValue }
    var shortName: String {
        switch self {
        case .requiredDay: L10n.string("Set day")
        case .excludedDay: L10n.string("Avoid")
        case .maximumPerWeek: L10n.string("Maximum")
        case .minimumPerWeek: L10n.string("Minimum")
        case .maximumPrepTime: L10n.string("Time")
        }
    }
    var symbol: String {
        switch self {
        case .requiredDay: "calendar.badge.checkmark"
        case .excludedDay: "calendar.badge.minus"
        case .maximumPerWeek: "lessthan.circle"
        case .minimumPerWeek: "greaterthan.circle"
        case .maximumPrepTime: "clock"
        }
    }
    var usesMatcher: Bool { self != .maximumPrepTime }
    func generatedTitle(matcher: MealMatcher, meals: [Meal]) -> String {
        let target = matcher.label(meals: meals).lowercased()
        switch self {
        case .requiredDay: L10n.string("Set %@", target)
        case .excludedDay: L10n.string("Without %@", target)
        case .maximumPerWeek: L10n.string("Limit %@", target)
        case .minimumPerWeek: L10n.string("Enough %@", target)
        case .maximumPrepTime: L10n.string("Quick dinner")
        }
    }
}

private enum TargetKind: String, CaseIterable, Identifiable {
    case category, exactMeal
    var id: String { rawValue }
    var name: String {
        self == .category ? L10n.string("Category") : L10n.string("Specific meal")
    }
}
