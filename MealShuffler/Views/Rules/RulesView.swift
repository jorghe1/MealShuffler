import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAddRule = false
    @State private var editingRule: PlanningRule?

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
                            Button("Edit") { editingRule = rule }.font(.caption)
                            if let start = rule.nextActiveWeek(from: store.plan.startDate) {
                                Text(L10n.string("Next active week: %@", WeekAnchor.label(forWeekStarting: start))).font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            if let interval = rule.repeatEveryWeeks, interval > 1 {
                                Text(L10n.string("Every %ld weeks", interval)).font(.caption)
                            }
                            Menu {
                                Button("Required") { store.setRuleStrength(.required, ruleID: rule.id) }
                                if rule.supportsPreference { Button("Preferred") { store.setRuleStrength(.preferred, ruleID: rule.id) } }
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
        .sheet(item: $editingRule) { AddRuleView(editing: $0).environmentObject(store) }
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

struct AddRuleView: View {
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
    @State private var interval = 1
    @State private var firstWeek = WeekAnchor.startOfCurrentWeek()
    @State private var rejection: String?
    let editing: PlanningRule?
    @State private var showingAdvanced = false
    @State private var showingMoreTemplates = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(editing: PlanningRule? = nil) {
        self.editing = editing
        guard let rule = editing else { return }
        _strength = State(initialValue: rule.strength)
        _interval = State(initialValue: rule.repeatEveryWeeks ?? 1)
        _firstWeek = State(initialValue: rule.firstWeek ?? WeekAnchor.startOfCurrentWeek())
        switch rule.constraint {
        case .requiredOn(let day, _): _mode = State(initialValue: .requiredDay); _scope = State(initialValue: day)
        case .excludedOn(let day, _): _mode = State(initialValue: .excludedDay); _scope = State(initialValue: day)
        case .maximumPerWeek(_, let value): _mode = State(initialValue: .maximumPerWeek); _count = State(initialValue: value)
        case .minimumPerWeek(_, let value): _mode = State(initialValue: .minimumPerWeek); _count = State(initialValue: value)
        case .maximumPrepTime(let day, let value): _mode = State(initialValue: .maximumPrepTime); _scope = State(initialValue: day); _minutes = State(initialValue: value)
        case .dinnerMode(let day, let value): _mode = State(initialValue: .dinnerPlan); _scope = State(initialValue: day); _dinnerMode = State(initialValue: value)
        case .noRepeatWithin(let value): _mode = State(initialValue: .noRepeat); _weeks = State(initialValue: value)
        case .requiredEvery(let value, _): _mode = State(initialValue: .bringBack); _weeks = State(initialValue: value)
        case .notOnConsecutiveDays: _mode = State(initialValue: .notConsecutive)
        }
        if let matcher = rule.constraint.matcher {
            switch matcher {
            case .tag(let value): _targetKind = State(initialValue: .category); _tag = State(initialValue: value)
            case .exactMeal(let value): _targetKind = State(initialValue: .exactMeal); _mealID = State(initialValue: value)
            case .ingredient(let value): _targetKind = State(initialValue: .ingredient); _ingredientText = State(initialValue: value)
            case .customTag(let value): _targetKind = State(initialValue: .customTag); _customTagText = State(initialValue: value)
            case .dislikedBy(let value): _targetKind = State(initialValue: .person); _memberID = State(initialValue: value)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("What should the rule do?")
                            .font(.system(.title, design: .rounded, weight: .bold))
                    Text("Choose a template, then adjust its details. The sentence previews your rule.")
                            .foregroundStyle(AppTheme.muted)
                    }

                    modeChips
                    sentenceCard
                    if mode.usesMatcher { targetPicker }
                    if mode != .dinnerPlan { strengthCard }
                    else { Text("Day plans are fixed commitments. Make an exception in the week when plans change.").font(.caption) }
                    DisclosureGroup("Schedule", isExpanded: $showingAdvanced) {
                        Stepper(L10n.string("Every %ld weeks", interval), value: $interval, in: 1...8)
                        DatePicker("Starting week", selection: $firstWeek, displayedComponents: .date)
                    }.padding().mealCard()

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
                        switch store.addRule(previewRule, replacingID: editing?.id) {
                        case .added:
                            dismiss()
                        case .duplicate(let existing):
                            rejection = L10n.string("You already have this rule: %@", existing)
                        case .contradiction(let existing):
                            rejection = L10n.string("This cannot hold alongside “%@”.", existing)
                        }
                    } label: {
                        Text(editing == nil ? L10n.string("Add rule") : L10n.string("Save")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: AppTheme.controlRadius))
                    .disabled(!isComplete)
                }
                .padding(20)
            }
            .appBackground()
            .navigationTitle(editing == nil ? L10n.string("New rule") : L10n.string("Edit rule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: mode) { _, _ in rejection = nil }
        }
    }

    private let commonModes: [RuleMode] = [.requiredDay, .excludedDay, .maximumPrepTime, .dinnerPlan]
    private func templateButtons(_ options: [RuleMode]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(options) { option in
                Button { withAnimation(reduceMotion ? nil : .snappy) { mode = option } } label: {
                    Label(option.shortName, systemImage: option.symbol)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .chipStyle(selected: mode == option)
                }.buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? [.isButton, .isSelected] : [.isButton])
            }
        }
    }
    private var modeChips: some View {
        VStack(alignment: .leading, spacing: 12) {
            templateButtons(commonModes)
            DisclosureGroup("More rule templates", isExpanded: $showingMoreTemplates) {
                templateButtons(RuleMode.allCases.filter { !commonModes.contains($0) })
            }
        }.onAppear { if !commonModes.contains(mode) { showingMoreTemplates = true } }
    }

    private var sentenceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(previewRule.summary(meals: store.meals, context: store.matchContext))
                .font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if [.requiredDay, .excludedDay, .maximumPrepTime, .dinnerPlan].contains(mode) {
                LabeledContent("Choose days") { scopeMenu }
            }
            if mode.usesMatcher { LabeledContent("Target") { targetMenu } }
            if mode == .dinnerPlan { LabeledContent("Plan") { dinnerModeMenu } }
            if mode == .maximumPerWeek || mode == .minimumPerWeek { LabeledContent("per week") { countMenu } }
            if mode == .maximumPrepTime { minuteMenu }
            if mode == .noRepeat || mode == .bringBack { weekMenu }
            Text("Weekly counts measure dinners cooked. Leftovers are counted only by ingredient exclusions.")
                .font(.caption).foregroundStyle(AppTheme.muted)
        }.padding(20).mealCard()
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What is the rule about?").font(.headline)
            Picker("Target", selection: $targetKind) {
                ForEach(TargetKind.available(hasMembers: !selectableMembers.isEmpty)) {
                    Text($0.name).tag($0)
                }
            }
            .pickerStyle(.menu)

            switch targetKind {
            case .ingredient:
                TextField("Ingredient, for example almonds", text: $ingredientText)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)
                Text("Matches ingredient names. This does not verify allergens or hidden ingredients.")
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
            Text("Uses this person's saved dislikes.")
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
            Menu("Choose days") {
                ForEach(Weekday.ordered()) { day in
                    Button {
                        var days = scope.days()
                        if days.contains(day), days.count > 1 { days.remove(day) } else { days.insert(day) }
                        scope = .selected(days)
                    } label: { Label(day.name, systemImage: scope.covers(day) ? "checkmark" : "circle") }
                }
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
            SentenceToken(text: matcher.label(meals: store.meals, context: store.matchContext))
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
        var rule = PlanningRule(
            id: editing?.id ?? UUID(),
            title: mode.generatedTitle(matcher: matcher, meals: store.meals, context: store.matchContext),
            strength: strength,
            constraint: constraint
        )
        rule.repeatEveryWeeks = interval
        rule.firstWeek = WeekAnchor.startOfWeek(containing: firstWeek)
        rule.isEnabled = editing?.isEnabled ?? true
        return rule
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
        case .category: return true
        case .exactMeal: return store.meals.contains { $0.id == mealID }
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
        let target = matcher.sentenceLabel(meals: meals, context: context)
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
