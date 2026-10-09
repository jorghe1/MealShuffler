import SwiftUI

/// Type a rule the way you would say it: "taco Friday", "max 2 chicken a week".
///
/// What the parser understood is shown inside the sentence as it is typed -- foods, days and
/// numbers in colour, anything it could not read underlined -- the way Todoist and Fantastical
/// highlight "every Friday" before you press return. It used to answer with a confident
/// checkmark and a sentence of its own ("Vi lager lak på torsdag"), which is how a misreading
/// got saved. Where a word can be read more than one way ("laks": salmon, or any fish?) it asks
/// with one tap rather than guessing, and a requirement no dinner in the library can meet is
/// refused instead of leaving a day empty.
struct RuleComposer: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    /// The reading the household picked for a sentence, by its position in the batch.
    @State private var choices: [Int: MealMatcher] = [:]
    /// "Må" or "Helst" for everything typed, when the household changed it.
    @State private var strengthOverride: RuleStrength?
    @State private var feedback: String?
    /// The text the feedback was about; it disappears as soon as the text changes.
    @State private var feedbackText = ""
    @State private var justAdded: String?
    @FocusState private var isFocused: Bool

    private typealias Reading = RuleSentenceParser.Reading

    private var readings: [(text: String, reading: Reading)] {
        RuleSentenceParser.readAll(text, meals: store.meals, customTags: store.customTagsInUse, members: store.household.members)
    }

    var body: some View {
        let current = readings
        let rules = current.enumerated().compactMap { index, entry in rule(at: index, entry.reading) }
        let addable = rules.filter { blockingReason($0) == nil }

        VStack(alignment: .leading, spacing: AppTheme.Space.m) {
            Text("Write a rule").font(.headline).foregroundStyle(AppTheme.ink)
            TextField("Taco Friday, fish twice a week…", text: $text)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .focused($isFocused)
                .onSubmit(add)
                .onChange(of: text) { _, _ in choices = [:] }

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState
            } else {
                if let feedback, feedbackText == text {
                    Label(feedback, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.warning)
                }
                ForEach(Array(current.enumerated()), id: \.offset) { index, entry in
                    readingView(index: index, entry: entry)
                }
                if rules.contains(where: \.supportsPreference) { strengthPicker(for: rules) }
                Button(action: add) {
                    Text(addable.count > 1 ? L10n.string("Add %ld rules", addable.count) : L10n.string("Add rule"))
                }
                .buttonStyle(.primary)
                .disabled(addable.isEmpty)
            }
        }
        .padding(AppTheme.Space.l)
        .mealCard()
        .animation(reduceMotion ? nil : .snappy, value: text)
    }

    // MARK: - One sentence

    @ViewBuilder
    private func readingView(index: Int, entry: (text: String, reading: Reading)) -> some View {
        let reading = entry.reading
        VStack(alignment: .leading, spacing: AppTheme.Space.s) {
            if !reading.tokens.isEmpty {
                highlighted(reading.tokens)
                    .font(.body)
                    .accessibilityLabel(entry.text)
            } else {
                Text(entry.text).font(.body.weight(.semibold)).foregroundStyle(AppTheme.ink)
            }

            switch reading.outcome {
            case .rule:
                if let rule = rule(at: index, reading) {
                    Label(rule.summary(meals: store.meals, context: store.matchContext), systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                    if let reason = blockingReason(rule) {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.warning)
                    } else {
                        Text(detail(for: rule)).font(.caption).foregroundStyle(AppTheme.muted)
                    }
                }
                if let food = reading.food, !food.alternatives.isEmpty {
                    clarification(index: index, food: food)
                }
            case .incomplete(let hint):
                Label(hint, systemImage: "ellipsis.bubble")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
            case .notUnderstood:
                Label("I did not understand that one. Try saying it more simply, or pick a suggestion.", systemImage: "questionmark.bubble")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
            }

            if !reading.additionalFoods.isEmpty {
                Text(L10n.string("A rule is about one food, so %@ was left out. Write it as a rule of its own.",
                                 reading.additionalFoods.map { "«\($0.word)»" }.joined(separator: ", ")))
                    .font(.caption).foregroundStyle(AppTheme.warning)
            }
            if !reading.ignored.isEmpty {
                Text(L10n.string("Not understood: %@", reading.ignored.joined(separator: ", ")))
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
        }
        .padding(AppTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
    }

    /// "What do you mean by «laks»?" with each reading and how many dinners it fits.
    private func clarification(index: Int, food: RuleSentenceParser.Food) -> some View {
        let options = [food.matcher] + food.alternatives
        let selected = choices[index] ?? food.matcher
        return VStack(alignment: .leading, spacing: AppTheme.Space.s) {
            Text(L10n.string("What do you mean by “%@”?", food.word))
                .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Space.s) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            Haptics.check()
                            choices[index] = option
                        } label: {
                            Text(L10n.string("%@ (%ld)", optionLabel(option), matchCount(option)))
                                .chipStyle(selected: option == selected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option == selected ? [.isButton, .isSelected] : [.isButton])
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func optionLabel(_ matcher: MealMatcher) -> String {
        switch matcher {
        case .tag(let tag): return L10n.string("%@ in general", tag.name)
        case .ingredient(let word): return L10n.string("Dishes with %@", word)
        case .exactMeal(let id): return L10n.string("Only %@", store.meal(id: id)?.name ?? L10n.string("Selected meal"))
        default: return matcher.label(meals: store.meals, context: store.matchContext)
        }
    }

    /// The typed words, coloured by how they were read.
    private func highlighted(_ tokens: [RuleSentenceParser.Token]) -> Text {
        var string = AttributedString()
        for (index, token) in tokens.enumerated() {
            var piece = AttributedString(token.text + (index < tokens.count - 1 ? " " : ""))
            switch token.role {
            case .food:
                piece.foregroundColor = AppTheme.accent
                piece.font = Font.body.weight(.semibold)
            case .day:
                piece.foregroundColor = AppTheme.categoryFish
                piece.font = Font.body.weight(.semibold)
            case .number:
                piece.foregroundColor = AppTheme.categoryMeat
                piece.font = Font.body.weight(.semibold)
            case .modifier:
                piece.foregroundColor = AppTheme.ink
            case .filler:
                piece.foregroundColor = AppTheme.muted
            case .unknown:
                piece.foregroundColor = AppTheme.warning
                piece.underlineStyle = Text.LineStyle(pattern: .dot, color: AppTheme.warning)
            }
            string += piece
        }
        return Text(string)
    }

    private func strengthPicker(for rules: [PlanningRule]) -> some View {
        let current = strengthOverride ?? rules.first?.strength ?? .required
        return VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
            Picker("How strict?", selection: Binding(get: { current }, set: { strengthOverride = $0 })) {
                ForEach(RuleStrength.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(current == .required
                 ? L10n.string("Must: the week always follows it, or says why it could not.")
                 : L10n.string("If possible: followed when it fits, and never blocks a good week."))
                .font(.caption).foregroundStyle(AppTheme.muted)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if let justAdded {
            Label(L10n.string("Added: %@", justAdded), systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
        } else {
            Text("Days, limits, foods to avoid, day plans and variety all work. Several rules can go on one line.")
                .font(.caption).foregroundStyle(AppTheme.muted)
        }
        suggestionRow
    }

    // MARK: - Reading the rules

    /// The rule a sentence would add, with the household's choices applied.
    private func rule(at index: Int, _ reading: Reading) -> PlanningRule? {
        guard var rule = reading.rule else { return nil }
        if let chosen = choices[index] { rule.constraint = rule.constraint.replacingMatcher(chosen) }
        if let strengthOverride, rule.supportsPreference { rule.strength = strengthOverride }
        return rule
    }

    private func matchCount(_ matcher: MealMatcher) -> Int {
        store.meals.filter { matcher.matches($0, context: store.matchContext) }.count
    }

    /// Why a rule cannot be added as it stands, if it cannot.
    private func blockingReason(_ rule: PlanningRule) -> String? {
        guard rule.constraint.needsAMatch, let matcher = rule.constraint.matcher, matchCount(matcher) == 0 else { return nil }
        if case .dislikedBy = matcher { return nil }
        return L10n.string("No dinner in your library fits “%@”. Add one first, or say it another way.",
                           matcher.label(meals: store.meals, context: store.matchContext))
    }

    /// Strength, schedule and how many dinners fit, so a rule nobody can satisfy is obvious.
    private func detail(for rule: PlanningRule) -> String {
        var parts = [rule.strength.name]
        if let interval = rule.repeatEveryWeeks, interval > 1 { parts.append(L10n.string("Every %ld weeks", interval)) }
        if let matcher = rule.constraint.matcher {
            let fitting = matchCount(matcher)
            switch rule.constraint {
            case .excludedOn, .maximumPerWeek(_, 0):
                parts.append(fitting == 0
                    ? L10n.string("No dinners in your library are affected yet")
                    : L10n.string("Keeps %ld dinners off the plan", fitting))
            default:
                parts.append(L10n.string("%ld of %ld meals match", fitting, store.meals.count))
            }
            if case .ingredient = matcher {
                parts.append(L10n.string("Matches ingredient names. This does not verify allergens or hidden ingredients."))
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Suggestions the household does not already have.
    private var availableSuggestions: [String] {
        let existing = store.rules.map(\.constraint)
        return RuleSentenceParser.suggestions.filter { suggestion in
            guard let rule = RuleSentenceParser.parse(suggestion, meals: store.meals).rule else { return false }
            return !existing.contains(rule.constraint)
        }
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Space.s) {
                ForEach(availableSuggestions, id: \.self) { suggestion in
                    Button {
                        text = suggestion
                        isFocused = true
                        Haptics.check()
                    } label: {
                        Text(suggestion)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, AppTheme.Space.m)
                            .frame(minHeight: AppTheme.tapTarget)
                            .background(AppTheme.accentSoft)
                            .foregroundStyle(AppTheme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, AppTheme.Space.xxs)
        }
        .scrollClipDisabled()
    }

    // MARK: - Adding

    private func add() {
        let current = readings
        var added: [String] = []
        var problems: [String] = []
        var remaining: [String] = []
        for (index, entry) in current.enumerated() {
            guard let rule = rule(at: index, entry.reading) else {
                remaining.append(entry.text)
                if case .incomplete(let hint) = entry.reading.outcome { problems.append(hint) }
                continue
            }
            if let reason = blockingReason(rule) {
                remaining.append(entry.text)
                problems.append(reason)
                continue
            }
            switch store.addRule(rule) {
            case .added:
                added.append(rule.title)
            case .duplicate(let existing):
                remaining.append(entry.text)
                problems.append(L10n.string("You already have this rule: %@", existing))
            case .contradiction(let existing):
                remaining.append(entry.text)
                problems.append(L10n.string("This cannot hold alongside “%@”.", existing))
            }
        }
        guard !added.isEmpty || !problems.isEmpty else { return }
        if !added.isEmpty {
            Haptics.success()
            justAdded = added.joined(separator: ", ")
            isFocused = !remaining.isEmpty
        }
        choices = [:]
        strengthOverride = nil
        // Anything added leaves the field; what could not be added is said about what remains.
        text = remaining.joined(separator: "; ")
        if !remaining.isEmpty, !added.isEmpty {
            problems.insert(L10n.string("Added: %@", added.joined(separator: ", ")), at: 0)
        }
        feedback = problems.isEmpty ? nil : problems.joined(separator: " ")
        feedbackText = text
    }
}
