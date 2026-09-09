import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAddRule = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rules written as plain sentences")
                        .font(.system(.title2, design: .rounded, weight: .bold))
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
                            .background(rule.isEnabled ? AppTheme.accentSoft : AppTheme.raised)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(rule.summary(meals: store.meals, context: store.matchContext))
                                .font(.headline).foregroundStyle(AppTheme.ink)
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
                            set: { store.setRule(rule, enabled: $0) }
                        ))
                        .labelsHidden()
                        .accessibilityLabel(rule.summary(meals: store.meals, context: store.matchContext))
                    }
                    .padding(.vertical, 5)
                }
                .onDelete(perform: store.deleteRules)
            }

            Section {
                Button { showingAddRule = true } label: {
                    Label("Create a new rule", systemImage: "plus.circle.fill").font(.headline)
                }
            } footer: {
                Text("Rules cover the day plan too: eating out, nobody home, or living off leftovers can be stated once here instead of set on the day every week.")
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Rules")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddRule) { AddRuleView().environmentObject(store) }
    }

    private func symbol(for constraint: RuleConstraint) -> String {
        switch constraint {
        case .requiredOn: "calendar.badge.checkmark"
        case .excludedOn: "calendar.badge.minus"
        case .maximumPerWeek: "lessthan.circle"
        case .minimumPerWeek: "greaterthan.circle"
        case .maximumPrepTime: "clock"
        case .dinnerMode: "house"
        case .noRepeatWithin: "arrow.triangle.2.circlepath"
        case .requiredEvery: "arrow.clockwise.circle"
        case .notOnConsecutiveDays: "arrow.left.arrow.right"
        }
    }
}

private struct AddRuleView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: RuleMode = .requiredDay
    @State private var scope: DayScope = .day(.monday)
    @State private var targetKind: TargetKind = .category
    @State private var tag: MealTag = .fish
    @State private var mealID: UUID = SampleMeals.all[0].id
    @State private var ingredientText = ""
    @State private var customTagText = ""
    @State private var memberID: UUID?
    @State private var dinnerMode: DayDinnerMode = .takeaway
    @State private var count = 1
    @State private var minutes = 30
    @State private var weeks = 3
    @State private var strength: RuleStrength = .required
    @State private var rejection: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("What should the rule do?")
                            .font(.system(.title, design: .rounded, weight: .bold))
                        Text("Choose a template and tap the green words to change the sentence.")
                            .foregroundStyle(AppTheme.muted)
                    }

                    modeChips
                    sentenceCard
                    if mode.usesMatcher { targetPicker }
                    strengthCard

                    if mode.usesMatcher {
                        Label(
                            L10n.string("%ld of %ld meals work with this choice", matchingMealCount, store.meals.count),
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(matchingMealCount == 0 ? AppTheme.warning : AppTheme.accent)
                    }

                    if let rejection {
                        Label(rejection, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.warning)
                    }

                    Button {
                        switch store.addRule(previewRule) {
                        case .added:
                            dismiss()
                        case .duplicate(let existing):
                            rejection = L10n.string("You already have this rule: %@", existing)
                        case .contradiction(let existing):
                            rejection = L10n.string("This cannot hold alongside “%@”.", existing)
                        }
                    } label: {
                        Text("Add rule").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: AppTheme.controlRadius))
                    .disabled(!isComplete)
                }
                .padding(20)
            }
            .appBackground()
            .navigationTitle("New rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: mode) { _, _ in rejection = nil }
        }
    }

    private var modeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RuleMode.allCases) { option in
                    Button { withAnimation(.snappy) { mode = option } } label: {
                        Label(option.shortName, systemImage: option.symbol)
                            .chipStyle(selected: mode == option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mode == option ? [.isButton, .isSelected] : [.isButton])
                }
            }
        }
    }

    private var sentenceCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("RULE").font(.caption.bold()).tracking(1).foregroundStyle(AppTheme.accent)
            Group {
                switch mode {
                case .requiredDay:
                    HStack(spacing: 7) { Text("On"); scopeMenu; Text("we'll have") }
                    targetMenu
                case .excludedDay:
                    HStack(spacing: 7) { Text("On"); scopeMenu; Text("we won't have") }
                    targetMenu
                case .maximumPerWeek:
                    HStack(spacing: 7) { Text("Maximum"); countMenu; targetMenu; Text("per week") }
                case .minimumPerWeek:
                    HStack(spacing: 7) { Text("At least"); countMenu; targetMenu; Text("per week") }
                case .maximumPrepTime:
                    HStack(spacing: 7) { Text("On"); scopeMenu; Text("dinner should take") }
                    HStack(spacing: 7) { Text("at most"); minuteMenu }
                case .dinnerPlan:
                    HStack(spacing: 7) { Text("On"); scopeMenu; Text("we're") }
                    dinnerModeMenu
                case .noRepeat:
                    HStack(spacing: 7) { Text("Don't repeat a dinner within"); weekMenu }
                case .bringBack:
                    HStack(spacing: 7) { Text("Have"); targetMenu }
                    HStack(spacing: 7) { Text("at least every"); weekMenu }
                case .notConsecutive:
                    HStack(spacing: 7) { Text("Never"); targetMenu }
                    Text("two days running")
                }
            }
            .font(.title3.weight(.semibold))
        }
        .padding(20).mealCard()
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What is the rule about?").font(.headline)
            Picker("Target", selection: $targetKind) {
                ForEach(TargetKind.available(hasMembers: !selectableMembers.isEmpty)) {
                    Text($0.name).tag($0)
                }
            }
            .pickerStyle(.segmented)

            switch targetKind {
            case .ingredient:
                TextField("Ingredient, for example almonds", text: $ingredientText)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)
                Text("Matches any meal whose ingredients mention this word. This is where an allergy belongs.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            case .customTag:
                TextField("Label, for example kid-friendly", text: $customTagText)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)
                if !store.customTagsInUse.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.customTagsInUse, id: \.self) { label in
                                Button { customTagText = label } label: {
                                    Text(label).chipStyle(selected: customTagText == label)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Text("Add labels to a meal when you edit it.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            case .person:
                Picker("Person", selection: $memberID) {
                    Text("Choose someone").tag(nil as UUID?)
                    ForEach(selectableMembers) { Text($0.displayName).tag($0.id as UUID?) }
                }
                Text("Uses what that person swiped away during onboarding.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            case .category, .exactMeal:
                EmptyView()
            }
        }
        .padding(18).mealCard()
    }

    private var strengthCard: some View {
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
    }

    // MARK: - Tokens

    private var scopeMenu: some View {
        Menu {
            ForEach(DayScope.selectableCases) { option in
                Button(option.name) { scope = option }
            }
        } label: { SentenceToken(text: scope.name) }
    }

    private var targetMenu: some View {
        Menu {
            switch targetKind {
            case .category:
                ForEach(MealTag.allCases) { item in Button(item.name) { tag = item } }
            case .exactMeal:
                ForEach(store.meals) { meal in Button("\(meal.emoji) \(meal.name)") { mealID = meal.id } }
            case .ingredient, .customTag, .person:
                Button("Set it above") {}
                    .disabled(true)
            }
        } label: {
            SentenceToken(text: matcher.label(meals: store.meals, context: store.matchContext).lowercased())
        }
    }

    private var dinnerModeMenu: some View {
        Menu {
            ForEach(DayDinnerMode.allCases) { option in
                Button(option.name) { dinnerMode = option }
            }
        } label: { SentenceToken(text: dinnerMode.name.lowercased()) }
    }

    private var countMenu: some View {
        Menu {
            // Zero is "never", which needed seven separate day rules before.
            ForEach(0...7, id: \.self) { value in Button("\(value)") { count = value } }
        } label: { SentenceToken(text: "\(count)") }
    }

    private var minuteMenu: some View {
        Menu {
            ForEach(Array(stride(from: 15, through: 120, by: 5)), id: \.self) { value in
                Button("\(value) min") { minutes = value }
            }
        } label: { SentenceToken(text: L10n.string("%ld minutes", minutes)) }
    }

    private var weekMenu: some View {
        Menu {
            ForEach(1...8, id: \.self) { value in
                Button(value == 1 ? L10n.string("1 week") : L10n.string("%ld weeks", value)) { weeks = value }
            }
        } label: {
            SentenceToken(text: weeks == 1 ? L10n.string("1 week") : L10n.string("%ld weeks", weeks))
        }
    }

    // MARK: - Assembly

    private var selectableMembers: [HouseholdMember] {
        store.household.members.filter { store.matchContext.dislikes[$0.id]?.isEmpty == false }
    }

    private var matcher: MealMatcher {
        switch targetKind {
        case .category: .tag(tag)
        case .exactMeal: .exactMeal(mealID)
        case .ingredient: .ingredient(ingredientText.trimmingCharacters(in: .whitespacesAndNewlines))
        case .customTag: .customTag(customTagText.trimmingCharacters(in: .whitespacesAndNewlines))
        case .person: .dislikedBy(memberID: memberID ?? UUID())
        }
    }

    private var previewRule: PlanningRule {
        let constraint: RuleConstraint
        switch mode {
        case .requiredDay: constraint = .requiredOn(day: scope, matcher: matcher)
        case .excludedDay: constraint = .excludedOn(day: scope, matcher: matcher)
        case .maximumPerWeek: constraint = .maximumPerWeek(matcher: matcher, count: count)
        case .minimumPerWeek: constraint = .minimumPerWeek(matcher: matcher, count: count)
        case .maximumPrepTime: constraint = .maximumPrepTime(day: scope, minutes: minutes)
        case .dinnerPlan: constraint = .dinnerMode(day: scope, mode: dinnerMode)
        case .noRepeat: constraint = .noRepeatWithin(weeks: weeks)
        case .bringBack: constraint = .requiredEvery(weeks: weeks, matcher: matcher)
        case .notConsecutive: constraint = .notOnConsecutiveDays(matcher: matcher)
        }
        return PlanningRule(
            title: mode.generatedTitle(matcher: matcher, meals: store.meals, context: store.matchContext),
            strength: strength,
            constraint: constraint
        )
    }

    private var matchingMealCount: Int {
        switch previewRule.constraint {
        case .maximumPrepTime(_, let minutes): store.meals.filter { $0.prepMinutes <= minutes }.count
        case .excludedOn(_, let matcher): store.meals.filter { !matcher.matches($0, context: store.matchContext) }.count
        default:
            previewRule.constraint.matcher.map { candidate in
                store.meals.filter { candidate.matches($0, context: store.matchContext) }.count
            } ?? store.meals.count
        }
    }

    /// A rule the household has not finished writing should not be addable.
    private var isComplete: Bool {
        guard mode.usesMatcher else { return true }
        switch targetKind {
        case .ingredient: return !ingredientText.trimmingCharacters(in: .whitespaces).isEmpty
        case .customTag: return !customTagText.trimmingCharacters(in: .whitespaces).isEmpty
        case .person: return memberID != nil
        case .category, .exactMeal: return matchingMealCount > 0 || mode == .excludedDay
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
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
    }
}

private enum RuleMode: String, CaseIterable, Identifiable {
    case requiredDay, excludedDay, maximumPerWeek, minimumPerWeek, maximumPrepTime
    case dinnerPlan, noRepeat, bringBack, notConsecutive

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .requiredDay: L10n.string("Set day")
        case .excludedDay: L10n.string("Avoid")
        case .maximumPerWeek: L10n.string("Maximum")
        case .minimumPerWeek: L10n.string("Minimum")
        case .maximumPrepTime: L10n.string("Time")
        case .dinnerPlan: L10n.string("Day plan")
        case .noRepeat: L10n.string("No repeats")
        case .bringBack: L10n.string("Bring back")
        case .notConsecutive: L10n.string("Not in a row")
        }
    }

    var symbol: String {
        switch self {
        case .requiredDay: "calendar.badge.checkmark"
        case .excludedDay: "calendar.badge.minus"
        case .maximumPerWeek: "lessthan.circle"
        case .minimumPerWeek: "greaterthan.circle"
        case .maximumPrepTime: "clock"
        case .dinnerPlan: "house"
        case .noRepeat: "arrow.triangle.2.circlepath"
        case .bringBack: "arrow.clockwise.circle"
        case .notConsecutive: "arrow.left.arrow.right"
        }
    }

    var usesMatcher: Bool {
        switch self {
        case .maximumPrepTime, .dinnerPlan, .noRepeat: false
        default: true
        }
    }

    func generatedTitle(matcher: MealMatcher, meals: [Meal], context: MealMatcher.MatchContext) -> String {
        let target = matcher.label(meals: meals, context: context).lowercased()
        return switch self {
        case .requiredDay: L10n.string("Set %@", target)
        case .excludedDay: L10n.string("Without %@", target)
        case .maximumPerWeek: L10n.string("Limit %@", target)
        case .minimumPerWeek: L10n.string("Enough %@", target)
        case .maximumPrepTime: L10n.string("Quick dinner")
        case .dinnerPlan: L10n.string("Day plan")
        case .noRepeat: L10n.string("Keep it varied")
        case .bringBack: L10n.string("Bring back %@", target)
        case .notConsecutive: L10n.string("Spread out %@", target)
        }
    }
}

private enum TargetKind: String, CaseIterable, Identifiable {
    case category, exactMeal, ingredient, customTag, person

    var id: String { rawValue }

    var name: String {
        switch self {
        case .category: L10n.string("Category")
        case .exactMeal: L10n.string("Meal")
        case .ingredient: L10n.string("Ingredient")
        case .customTag: L10n.string("Label")
        case .person: L10n.string("Person")
        }
    }

    /// The person option only appears once somebody has opinions to reference.
    static func available(hasMembers: Bool) -> [TargetKind] {
        hasMembers ? allCases : allCases.filter { $0 != .person }
    }
}
