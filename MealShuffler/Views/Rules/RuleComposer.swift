import SwiftUI

/// Type a rule the way you would say it: "taco Friday", "max 2 chicken a week".
///
/// The template builder stays for the rare rule the grammar cannot read, but the common
/// ones are one line of text now. What was understood is always shown as the rule's own
/// sentence before it is added, so a misreading is caught at the keyboard rather than in a
/// strange week.
struct RuleComposer: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var feedback: String?
    /// The text the feedback was about; it disappears as soon as the text changes.
    @State private var feedbackText = ""
    @State private var justAdded: String?
    @FocusState private var isFocused: Bool

    private var readings: [(text: String, outcome: RuleSentenceParser.Outcome)] {
        RuleSentenceParser.parseAll(text, meals: store.meals, customTags: store.customTagsInUse)
    }

    private var understoodRules: [PlanningRule] { readings.compactMap { $0.outcome.rule } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Say it in your own words", systemImage: "text.bubble.fill")
                .font(.headline).foregroundStyle(AppTheme.ink)
            HStack(spacing: 8) {
                TextField("Taco Friday, fish twice a week…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "plus.circle.fill").font(.title)
                        .foregroundStyle(understoodRules.isEmpty ? AppTheme.muted : AppTheme.accent)
                        .iconButtonFrame()
                }
                .buttonStyle(.plain)
                .disabled(understoodRules.isEmpty)
                .accessibilityLabel("Add rule")
            }
            preview
                .animation(reduceMotion ? nil : .snappy, value: text)
            suggestionRow
        }
        .padding(16)
        .mealCard()
    }

    @ViewBuilder private var preview: some View {
        if let feedback, feedbackText == text {
            Label(feedback, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.warning)
        } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let justAdded {
                Label(L10n.string("Added: %@", justAdded), systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
            } else {
                Text("Days, limits, ingredient exclusions, day plans and variety all work. Try a suggestion.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
        } else if readings.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(readings.enumerated()), id: \.offset) { _, reading in
                    readingRow(reading.text, reading.outcome)
                }
            }
        } else if let reading = readings.first {
            switch reading.outcome {
            case .rule(let rule):
                VStack(alignment: .leading, spacing: 4) {
                    Label(rule.summary(meals: store.meals, context: store.matchContext), systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                    Text(detail(for: rule)).font(.caption).foregroundStyle(AppTheme.muted)
                }
                .accessibilityElement(children: .combine)
            case .incomplete(let hint):
                Label(hint, systemImage: "ellipsis.bubble")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
            case .notUnderstood:
                Label("Not sure what that means yet. Try one of the suggestions.", systemImage: "questionmark.bubble")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
            }
        }
    }

    /// One line per rule when several were typed at once.
    @ViewBuilder private func readingRow(_ piece: String, _ outcome: RuleSentenceParser.Outcome) -> some View {
        if let rule = outcome.rule {
            VStack(alignment: .leading, spacing: 4) {
                Label(rule.summary(meals: store.meals, context: store.matchContext), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                Text(detail(for: rule)).font(.caption).foregroundStyle(AppTheme.muted)
            }
        } else {
            Label(piece, systemImage: "questionmark.circle")
                .font(.subheadline).foregroundStyle(AppTheme.muted)
        }
    }

    /// Strength, schedule and how many dinners fit, so a rule nobody can satisfy is obvious.
    private func detail(for rule: PlanningRule) -> String {
        var parts = [rule.strength.name]
        if let interval = rule.repeatEveryWeeks, interval > 1 { parts.append(L10n.string("Every %ld weeks", interval)) }
        if let matcher = rule.constraint.matcher {
            let fitting = store.meals.filter { matcher.matches($0, context: store.matchContext) }.count
            parts.append(L10n.string("%ld of %ld meals match", fitting, store.meals.count))
        }
        if case .ingredient? = rule.constraint.matcher {
            parts.append(L10n.string("Matches ingredient names. This does not verify allergens or hidden ingredients."))
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
            HStack(spacing: 8) {
                ForEach(availableSuggestions, id: \.self) { suggestion in
                    Button {
                        text = suggestion
                        Haptics.check()
                    } label: {
                        Text(suggestion)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(minHeight: AppTheme.tapTarget)
                            .background(text == suggestion ? AppTheme.accent : AppTheme.accentSoft)
                            .foregroundStyle(text == suggestion ? AppTheme.onAccent : AppTheme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func add() {
        let rules = understoodRules
        guard !rules.isEmpty else { return }
        var added: [String] = []
        var problems: [String] = []
        var remaining: [String] = []
        for reading in readings {
            guard let rule = reading.outcome.rule else {
                remaining.append(reading.text)
                if case .incomplete(let hint) = reading.outcome { problems.append(hint) }
                continue
            }
            switch store.addRule(rule) {
            case .added:
                added.append(rule.summary(meals: store.meals, context: store.matchContext))
            case .duplicate(let existing):
                remaining.append(reading.text)
                problems.append(L10n.string("You already have this rule: %@", existing))
            case .contradiction(let existing):
                remaining.append(reading.text)
                problems.append(L10n.string("This cannot hold alongside “%@”.", existing))
            }
        }
        if !added.isEmpty {
            Haptics.success()
            justAdded = added.joined(separator: " ")
            isFocused = !remaining.isEmpty
        }
        // Anything added leaves the field; what could not be added is said about what remains.
        text = remaining.joined(separator: "; ")
        if !remaining.isEmpty, !added.isEmpty {
            problems.insert(L10n.string("Added: %@", added.joined(separator: " ")), at: 0)
        }
        feedback = problems.isEmpty ? nil : problems.joined(separator: " ")
        feedbackText = text
    }
}
