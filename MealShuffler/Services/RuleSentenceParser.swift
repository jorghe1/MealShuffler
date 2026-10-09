import Foundation

/// Reads a rule the way a household says it.
///
/// "Taco Friday", "fredagstaco", "max two chicken a week", "no pasta on weekdays". The
/// template builder can express every one of these, but it takes five taps and a mental
/// translation into its vocabulary, and a rule is the thing people most want to state in one
/// breath. This does the translation.
///
/// Deliberately a small, deterministic grammar rather than a model call: it works offline,
/// answers on every keystroke, and whatever it produces is shown back before anything is
/// saved -- with the words it understood highlighted and the ones it ignored listed, so a
/// misreading is visible, never silent. English and Norwegian Bokmål are read regardless of the
/// device language, because a household types in whichever it thinks in.
///
/// It used to guess where it should ask. "laks på torsdag" was read as an unknown word, had an
/// English plural "s" trimmed off and became "lak"; "pizza på fredag men ikke på mandag" banned
/// pizza on both days because the "ikke" was read for the whole sentence; "fisk på fredag og
/// kylling på mandag" silently dropped the chicken. Foods now come from `IngredientVocabulary`,
/// clauses are split before they are read, and every food the sentence names is reported, so
/// the composer can ask which reading was meant instead of picking one.
enum RuleSentenceParser {
    enum Outcome: Equatable {
        case rule(PlanningRule)
        /// Something was understood, but not enough to make a rule. Says what to add.
        case incomplete(hint: String)
        case notUnderstood

        var rule: PlanningRule? {
            if case .rule(let rule) = self { return rule }
            return nil
        }
    }

    /// How a typed word was read, for the composer's highlighting.
    enum Role: Int, Equatable, Comparable {
        case unknown, filler, modifier, number, day, food

        static func < (lhs: Role, rhs: Role) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// One typed word and how it was read.
    struct Token: Equatable, Identifiable {
        let id: Int
        let text: String
        let role: Role
    }

    /// A food the sentence names, and the other ways it could be read.
    struct Food: Equatable {
        /// What the household typed for it.
        let word: String
        let matcher: MealMatcher
        /// Broader or narrower readings: "laks" is also "fish", and perhaps one dish.
        var alternatives: [MealMatcher] = []
    }

    /// Everything the parser can say about one rule sentence.
    struct Reading: Equatable {
        var outcome: Outcome
        var tokens: [Token] = []
        /// Words that played no part in the rule.
        var ignored: [String] = []
        /// The food the rule is about.
        var food: Food?
        /// Further foods the sentence named. A rule is about one food, so for anything but a
        /// ban these were left out, and the composer says so.
        var additionalFoods: [Food] = []
        /// True when the food came from the clause before: "…men ikke på mandag".
        var inheritedFood = false

        var rule: PlanningRule? { outcome.rule }
    }

    /// Examples that parse, in the device language, for a row of tappable starting points.
    static var suggestions: [String] {
        [
            L10n.string("Taco Friday"),
            L10n.string("Fish on Tuesday"),
            L10n.string("Meatless Monday"),
            L10n.string("Healthy on weekdays"),
            L10n.string("Under 30 minutes on weekdays"),
            L10n.string("Max 2 chicken a week"),
            L10n.string("Leftovers on Wednesday"),
            L10n.string("Not pasta two days in a row"),
            L10n.string("Pizza every other Saturday"),
            L10n.string("No repeats within 3 weeks")
        ]
    }

    static func parse(
        _ text: String,
        meals: [Meal],
        customTags: [String] = [],
        members: [HouseholdMember] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Outcome {
        read(text, meals: meals, customTags: customTags, members: members, now: now, calendar: calendar).outcome
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func read(
        _ text: String,
        meals: [Meal],
        customTags: [String] = [],
        members: [HouseholdMember] = [],
        inheriting inherited: Food? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Reading {
        var sentence = RuleSentence(text)
        guard sentence.hasContent else { return Reading(outcome: .notUnderstood) }

        let member = sentence.takeMember(members)
        // Before the plain negations: "liker ikke" is a dislike, not a ban on the whole sentence.
        let dislike = sentence.takeAny(RuleLexicon.dislike) != nil
        let preferred = sentence.takeAny(RuleLexicon.preference) != nil || dislike
        let only = sentence.takeAny(RuleLexicon.only) != nil
        let interval = sentence.takeInterval()
        let scope = sentence.takeScope()

        var food: Food?
        var additional: [Food] = []
        var inheritedFood = false
        var titleText = text

        func reading(_ outcome: Outcome) -> Reading {
            Reading(
                outcome: outcome,
                tokens: sentence.tokens,
                ignored: sentence.ignoredWords,
                food: food,
                additionalFoods: additional,
                inheritedFood: inheritedFood
            )
        }

        func make(_ constraint: RuleConstraint, schedule: Int? = nil) -> Reading {
            var rule = PlanningRule(
                title: title(for: titleText),
                strength: preferred ? .preferred : .required,
                constraint: constraint
            )
            if let schedule, schedule > 1 {
                rule.repeatEveryWeeks = min(schedule, 8)
                rule.firstWeek = WeekAnchor.startOfWeek(containing: now, calendar: calendar)
            }
            return reading(.rule(rule))
        }

        // Day plans first: "no dinner" and "nobody home" carry a negation that belongs to them.
        if let mode = sentence.takeDinnerMode() {
            if sentence.takeAny(RuleLexicon.negation) != nil {
                return reading(.incomplete(hint: L10n.string("Day plans say what does happen, for example “takeaway on Friday”.")))
            }
            guard let scope else { return reading(.incomplete(hint: daysHint)) }
            return make(.dinnerMode(day: scope, mode: mode), schedule: interval)
        }

        if sentence.takeAny(RuleLexicon.repeats) != nil {
            // "Ikke samme rett to dager på rad" says the same thing twice; both halves are read.
            sentence.takeAny(RuleLexicon.consecutive)
            sentence.takeAny(RuleLexicon.negation)
            let weeks = sentence.takeWeekSpan() ?? 1
            return make(.noRepeatWithin(weeks: min(max(weeks, 1), 8)))
        }

        if let minutes = sentence.takeMinutes() {
            // "Maks 30 min": the limit word is part of the time, not something left over.
            sentence.takeAny(RuleLexicon.atMost + RuleLexicon.below)
            return make(.maximumPrepTime(day: scope ?? .everyDay, minutes: min(max(minutes, 5), 240)), schedule: interval)
        }

        // Before the negations, because "meat-free" is not "no meat": it means vegetarian.
        let meatFree = sentence.takeAny(RuleLexicon.meatFree, role: .food)
        let consecutive = sentence.takeAny(RuleLexicon.consecutive) != nil
        // Before the negations too: "no more than two" is a limit, not a ban, and so is
        // "ikke pasta mer enn to ganger".
        let bound = sentence.takeBound()
        let negated = dislike || sentence.takeAny(RuleLexicon.negation) != nil
        let allergy = sentence.takeAny(RuleLexicon.allergy) != nil
        let weekly = sentence.takeAny(RuleLexicon.weekly) != nil
        let count = sentence.takeCount(after: bound?.range, contextual: weekly || bound != nil)

        var foods = sentence.takeFoods(meals: meals, customTags: customTags)
        if let meatFree {
            foods.insert(Food(word: sentence.typedText(meatFree), matcher: .tag(.vegetarian)), at: 0)
        }
        if foods.isEmpty, let member, dislike || negated {
            // "Ola liker ikke" on its own: whatever Ola swiped left on.
            foods = [Food(word: member.displayName, matcher: .dislikedBy(memberID: member.id))]
        }
        if foods.isEmpty, let inherited {
            foods = [inherited]
            inheritedFood = true
            titleText = inherited.word + " " + text
        }
        food = foods.first
        additional = Array(foods.dropFirst())

        guard let matcher = food?.matcher else {
            let understood = scope != nil || consecutive || bound != nil || negated || allergy
                || weekly || count != nil || only || interval != nil || member != nil
            return reading(understood ? .incomplete(hint: whatHint) : .notUnderstood)
        }

        if consecutive { return make(.notOnConsecutiveDays(matcher: matcher)) }

        if negated || allergy {
            switch matcher {
            case .ingredient, .dislikedBy:
                return make(.excludedOn(day: scope ?? .everyDay, matcher: matcher), schedule: interval)
            default:
                if let scope, scope != .everyDay {
                    return make(.excludedOn(day: scope, matcher: matcher), schedule: interval)
                }
                return make(.maximumPerWeek(matcher: matcher, count: 0))
            }
        }

        if let interval, scope == nil {
            return make(.requiredEvery(weeks: min(max(interval, 1), 8), matcher: matcher))
        }

        if let count {
            switch bound?.kind {
            case .atMost:
                return make(.maximumPerWeek(matcher: matcher, count: min(count, 7)))
            case .below:
                return make(.maximumPerWeek(matcher: matcher, count: max(min(count, 8) - 1, 0)))
            case .above:
                return make(.minimumPerWeek(matcher: matcher, count: min(max(count + 1, 1), 7)))
            case .atLeast, nil:
                return make(.minimumPerWeek(matcher: matcher, count: min(max(count, 1), 7)))
            }
        }
        if bound != nil { return reading(.incomplete(hint: L10n.string("Add a number, for example “max 2 a week”."))) }

        if let scope { return make(.requiredOn(day: scope, matcher: matcher), schedule: interval) }
        if only { return make(.requiredOn(day: .everyDay, matcher: matcher)) }
        return reading(.incomplete(hint: L10n.string("Add a day or a number, for example “on Fridays” or “twice a week”.")))
    }

    /// Several rules in one line: "taco Friday, fish twice a week; no nuts".
    ///
    /// Split at commas, semicolons and line breaks -- but not at a comma inside a number, which
    /// is how Norwegian writes "1,5 time". Then each piece is split at "men"/"but", where the
    /// second clause borrows the first one's food ("pizza på fredag, men ikke på mandag"), and at
    /// "og"/"and" when both sides are whole rules on their own ("taco på fredag og fisk på
    /// tirsdag") -- but not in "fish on Tuesday and Thursday", where the right side is not.
    static func parseAll(
        _ text: String,
        meals: [Meal],
        customTags: [String] = [],
        members: [HouseholdMember] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(text: String, outcome: Outcome)] {
        readAll(text, meals: meals, customTags: customTags, members: members, now: now, calendar: calendar)
            .map { (text: $0.text, outcome: $0.reading.outcome) }
    }

    static let batchLimit = 12

    static func readAll(
        _ text: String,
        meals: [Meal],
        customTags: [String] = [],
        members: [HouseholdMember] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(text: String, reading: Reading)] {
        func readOne(_ part: String, inheriting food: Food? = nil) -> Reading {
            read(part, meals: meals, customTags: customTags, members: members, inheriting: food, now: now, calendar: calendar)
        }

        var results: [(text: String, reading: Reading)] = []
        var previousFood: Food?
        for piece in pieces(of: text) {
            for clause in contrastClauses(of: piece) {
                let parts = clause.isContrast ? [clause.text] : conjunctionParts(of: clause.text, reading: { readOne($0) })
                for part in parts {
                    guard results.count < batchLimit else {
                        results.append((text: part, reading: Reading(outcome: .incomplete(hint: L10n.string("Add up to 12 rules at a time. The rest will stay here.")))))
                        continue
                    }
                    var reading = readOne(part, inheriting: clause.isContrast ? previousFood : nil)
                    if let food = reading.food, !reading.inheritedFood { previousFood = food }
                    let bans = banExpansion(of: &reading)
                    results.append((text: part, reading: reading))
                    for ban in bans where results.count < batchLimit {
                        results.append(ban)
                    }
                }
            }
        }
        return results
    }

    /// "Ingen nøtter eller sopp" is two bans. A ban on several foods is each of them banned, so
    /// the extra foods become rules of their own instead of being dropped.
    private static func banExpansion(of reading: inout Reading) -> [(text: String, reading: Reading)] {
        guard let rule = reading.rule, !reading.additionalFoods.isEmpty else { return [] }
        let extras = reading.additionalFoods
        let rebuilt: [(text: String, reading: Reading)]
        switch rule.constraint {
        case .excludedOn(let scope, _):
            rebuilt = extras.map { food in
                expanded(rule, food: food, constraint: .excludedOn(day: scope, matcher: food.matcher))
            }
        case .maximumPerWeek(_, 0):
            rebuilt = extras.map { food in
                let constraint: RuleConstraint
                if case .ingredient = food.matcher {
                    constraint = .excludedOn(day: .everyDay, matcher: food.matcher)
                } else {
                    constraint = .maximumPerWeek(matcher: food.matcher, count: 0)
                }
                return expanded(rule, food: food, constraint: constraint)
            }
        default:
            return []
        }
        reading.additionalFoods = []
        // The first rule now covers only its own food, so its title says only that food.
        if let first = reading.food {
            var retitled = rule
            retitled.title = title(for: L10n.string("No %@", first.word))
            reading.outcome = .rule(retitled)
        }
        return rebuilt
    }

    private static func expanded(_ rule: PlanningRule, food: Food, constraint: RuleConstraint) -> (text: String, reading: Reading) {
        let label = L10n.string("No %@", food.word)
        var copy = PlanningRule(title: title(for: label), strength: rule.strength, constraint: constraint)
        copy.repeatEveryWeeks = rule.repeatEveryWeeks
        copy.firstWeek = rule.firstWeek
        return (text: label, reading: Reading(outcome: .rule(copy), food: food))
    }

    /// Commas, semicolons and line breaks, but not "1,5".
    private static func pieces(of text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            let nextIsDigit = index + 1 < characters.count && characters[index + 1].isNumber
            let previousIsDigit = index > 0 && characters[index - 1].isNumber
            if character == ";" || character.isNewline || (character == "," && !(nextIsDigit && previousIsDigit)) {
                pieces.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        pieces.append(current)
        return pieces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static let contrastPattern = #"(?i)(^|\s)(men|but)\s+"#
    private static let conjunctionPattern = #"(?i)\s+(og|and|&)\s+"#

    /// "Pizza på fredag men ikke på mandag" → "pizza på fredag", then "ikke på mandag" as a
    /// clause that borrows the food. A piece that itself starts with "men" (after a comma)
    /// borrows from the piece before it.
    private static func contrastClauses(of piece: String) -> [(text: String, isContrast: Bool)] {
        var clauses: [(text: String, isContrast: Bool)] = []
        var remaining = Substring(piece)
        var isContrast = false
        while let match = remaining.range(of: contrastPattern, options: .regularExpression) {
            let before = remaining[..<match.lowerBound].trimmingCharacters(in: .whitespaces)
            if !before.isEmpty {
                clauses.append((text: before, isContrast: isContrast))
            }
            isContrast = true
            remaining = remaining[match.upperBound...]
        }
        let rest = remaining.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { clauses.append((text: rest, isContrast: isContrast)) }
        return clauses
    }

    /// Splits at "og"/"and" only where both sides read as complete rules of their own.
    private static func conjunctionParts(of clause: String, reading: (String) -> Reading) -> [String] {
        var searchStart = clause.startIndex
        while searchStart < clause.endIndex,
              let match = clause.range(of: conjunctionPattern, options: .regularExpression, range: searchStart..<clause.endIndex) {
            let left = clause[..<match.lowerBound].trimmingCharacters(in: .whitespaces)
            let right = String(clause[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !left.isEmpty, !right.isEmpty,
               reading(left).rule != nil, reading(right).rule != nil {
                return [left] + conjunctionParts(of: right, reading: reading)
            }
            searchStart = match.upperBound
        }
        return [clause]
    }

    private static var daysHint: String {
        L10n.string("Say which days, for example “on Fridays”.")
    }

    private static var whatHint: String {
        L10n.string("Say what the rule is about, for example “fish” or “pasta”.")
    }

    /// The household's own words make the best title: it is what they will recognise.
    static func title(for text: String) -> String {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        return trimmed.prefix(1).uppercased() + String(trimmed.dropFirst())
    }

    fileprivate static func fold(_ value: String) -> String {
        TextFolding.fold(value)
    }

    /// Words, numbers split from their units ("30min"), and dashes kept as their own token so
    /// "mon-fri" can be read as a range.
    fileprivate static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsDigit = false
        for character in text.lowercased() {
            if character == "'" || character == "’" { continue }
            if character.isLetter || character.isNumber {
                let isDigit = character.isNumber
                if !current.isEmpty && isDigit != currentIsDigit {
                    tokens.append(current)
                    current = ""
                }
                current.append(character)
                currentIsDigit = isDigit
            } else {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                if character == "-" || character == "–" || character == "—" { tokens.append("-") }
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Norwegian glues words together: the day to the dish ("fredagstaco", "tacofredag") and
    /// one food to another ("kyllingsuppe", "fiskesuppe", "kyllinggryte").
    fileprivate static func splitCompound(_ word: String) -> [String]? {
        guard word.count >= 6, RuleLexicon.weekday(word) == nil, !RuleLexicon.isKnown(word),
              IngredientVocabulary.entry(forFolded: word) == nil else { return nil }
        for stem in RuleLexicon.compoundDayStems {
            if word.hasPrefix(stem) {
                let rest = RuleLexicon.lemma(String(word.dropFirst(stem.count)))
                if RuleLexicon.isKnown(rest) || RuleLexicon.isFoodWord(rest) { return [stem, rest] }
            }
            if word.hasSuffix(stem) {
                let rest = RuleLexicon.lemma(String(word.dropLast(stem.count)))
                if RuleLexicon.isKnown(rest) || RuleLexicon.isFoodWord(rest) { return [rest, stem] }
            }
        }
        // "Nøttefritt", "glutenfri": the food and a negation, as "uten nøtter" would say it.
        for suffix in RuleLexicon.freeSuffixes where word.hasSuffix(suffix) && word.count - suffix.count >= 3 {
            let stem = String(word.dropLast(suffix.count))
            for candidate in [stem, stem.hasSuffix("e") ? String(stem.dropLast()) : stem] where RuleLexicon.isFoodWord(candidate) {
                return [candidate, "uten"]
            }
        }
        let characters = Array(word)
        var cut = characters.count - 3
        while cut >= 3 {
            let left = String(characters[..<cut])
            let right = String(characters[cut...])
            if RuleLexicon.isFoodWord(right) || RuleLexicon.dishNouns.contains(right) {
                if RuleLexicon.isFoodWord(left) { return [left, right] }
                // The linking letter: "fisk-e-suppe", "lam-me-gryte" is not handled, "kylling-s".
                if left.count > 3, left.hasSuffix("e") || left.hasSuffix("s") {
                    let stem = String(left.dropLast())
                    if RuleLexicon.isFoodWord(stem) { return [stem, right] }
                }
            }
            cut -= 1
        }
        return nil
    }
}

/// The typed sentence, with a record of which words have been accounted for and how.
///
/// Each reading step claims the words it understood, so later steps cannot read them twice:
/// the "two" in "two days in a row" is not also a weekly count.
private struct RuleSentence {
    enum BoundKind { case atMost, atLeast, below, above }

    /// Folded words, with Norwegian endings taken off a food word ("tacoen" → "taco").
    private(set) var words: [String] = []
    /// The typed spelling of each word, or of each part of a split compound.
    private(set) var original: [String] = []
    /// Which typed word each word came from: a compound gives several words one source.
    private var source: [Int] = []
    /// The typed words, for highlighting.
    private var typed: [String] = []
    private var used: Set<Int> = []
    private var roles: [Int: RuleSentenceParser.Role] = [:]

    init(_ text: String) {
        for (index, piece) in RuleSentenceParser.tokenize(text).enumerated() {
            typed.append(piece)
            let folded = RuleSentenceParser.fold(piece)
            if let parts = RuleSentenceParser.splitCompound(folded) {
                for part in parts {
                    words.append(RuleLexicon.lemma(part))
                    original.append(part)
                    source.append(index)
                }
            } else {
                words.append(RuleLexicon.lemma(folded))
                original.append(piece)
                source.append(index)
            }
        }
    }

    var hasContent: Bool { words.contains { $0 != "-" } }

    /// The typed words with the role each was read in.
    var tokens: [RuleSentenceParser.Token] {
        typed.indices.map { index in
            let parts = words.indices.filter { source[$0] == index }
            let role = parts.compactMap { roles[$0] }.max()
                ?? (parts.allSatisfy { RuleLexicon.isFiller(words[$0]) } ? .filler : .unknown)
            return RuleSentenceParser.Token(id: index, text: typed[index], role: role)
        }
    }

    /// Content words that played no part in the rule.
    var ignoredWords: [String] {
        var seen = Set<Int>()
        return words.indices.compactMap { index in
            guard !used.contains(index), !RuleLexicon.isFiller(words[index]),
                  seen.insert(source[index]).inserted else { return nil }
            return typed[source[index]]
        }
    }

    /// The typed text behind a range of words.
    func typedText(_ range: Range<Int>) -> String {
        var sources: [Int] = []
        for index in range where !sources.contains(source[index]) { sources.append(source[index]) }
        return sources.map { typed[$0] }.joined(separator: " ")
    }

    func find(_ phrase: String) -> Range<Int>? {
        let parts = phrase.split(separator: " ").map(String.init)
        guard !parts.isEmpty, parts.count <= words.count else { return nil }
        for start in 0...(words.count - parts.count) {
            let range = start..<(start + parts.count)
            guard range.allSatisfy({ !used.contains($0) }) else { continue }
            if Array(words[range]) == parts { return range }
        }
        return nil
    }

    private mutating func claim(_ range: Range<Int>, as role: RuleSentenceParser.Role) {
        used.formUnion(range)
        for index in range { roles[index] = role }
    }

    private mutating func claim(_ index: Int, as role: RuleSentenceParser.Role) {
        claim(index..<(index + 1), as: role)
    }

    /// Claims the longest matching phrase.
    @discardableResult
    mutating func takeAny(_ phrases: [String], role: RuleSentenceParser.Role = .modifier) -> Range<Int>? {
        let longestFirst = phrases.sorted { $0.split(separator: " ").count > $1.split(separator: " ").count }
        for phrase in longestFirst {
            if let range = find(phrase) {
                claim(range, as: role)
                return range
            }
        }
        return nil
    }

    private func isFree(_ indices: ClosedRange<Int>) -> Bool {
        indices.upperBound < words.count && indices.allSatisfy { !used.contains($0) }
    }

    // MARK: - People

    /// A household member named in the sentence: "Ola liker ikke sopp", "Olas dislikes".
    mutating func takeMember(_ members: [HouseholdMember]) -> HouseholdMember? {
        for member in members.sorted(by: { $0.displayName.count > $1.displayName.count }) {
            let name = RuleSentenceParser.tokenize(member.displayName).map(RuleSentenceParser.fold)
            // "Me" and "Meg" are names here and words everywhere else.
            guard !name.isEmpty, name.joined().count >= 2,
                  !(name.count == 1 && RuleLexicon.isFiller(name[0])) else { continue }
            if takeAny([name.joined(separator: " ")], role: .food) != nil { return member }
            if name.count == 1, takeAny([name[0] + "s"], role: .food) != nil { return member }
        }
        return nil
    }

    // MARK: - Days

    mutating func takeScope() -> DayScope? {
        var group: DayScope?
        if takeAny(RuleLexicon.everyDay, role: .day) != nil { group = .everyDay }
        else if takeAny(RuleLexicon.weekdays, role: .day) != nil { group = .weekdays }
        else if takeAny(RuleLexicon.weekend, role: .day) != nil { group = .weekend }

        var days: Set<Weekday> = []
        var index = 0
        while index + 2 < words.count {
            if isFree(index...(index + 2)),
               let first = RuleLexicon.weekday(words[index]),
               RuleLexicon.rangeConnectors.contains(words[index + 1]),
               let last = RuleLexicon.weekday(words[index + 2]) {
                days.formUnion(RuleLexicon.days(from: first, through: last))
                claim(index..<(index + 3), as: .day)
                index += 3
            } else {
                index += 1
            }
        }
        for position in words.indices where !used.contains(position) {
            // A typo in a day name is still that day: "torsdg", "fredga".
            if let day = RuleLexicon.weekday(words[position]) ?? RuleLexicon.nearWeekday(words[position]) {
                days.insert(day)
                claim(position, as: .day)
            }
        }

        guard !days.isEmpty else { return group }
        if let group { days.formUnion(group.days()) }
        if days == Set(Weekday.allCases) { return .everyDay }
        if days == DayScope.weekdays.days() { return .weekdays }
        if days == DayScope.weekendDays { return .weekend }
        if days.count == 1, let day = days.first { return .day(day) }
        return .selected(days)
    }

    /// "Every other week", "every 3 weeks", "annenhver uke", "hver 3. uke", "hver 2. fredag".
    mutating func takeInterval() -> Int? {
        if takeAny(RuleLexicon.everyOtherWeek) != nil { return 2 }
        if takeAny(RuleLexicon.everyThirdWeek) != nil { return 3 }
        if takeAny(RuleLexicon.everyFourthWeek) != nil { return 4 }
        for index in words.indices where isFree(index...(index + 2)) {
            guard RuleLexicon.every.contains(words[index]), let value = Int(words[index + 1]) else { continue }
            if (1...8).contains(value), RuleLexicon.weekUnits.contains(words[index + 2]) {
                claim(index..<(index + 3), as: .modifier)
                return value
            }
            // "Hver 2. fredag": the day stays for the scope to read.
            if (2...8).contains(value), RuleLexicon.weekday(words[index + 2]) != nil {
                claim(index..<(index + 2), as: .modifier)
                return value
            }
        }
        return nil
    }

    /// "Within 3 weeks", "for a month".
    mutating func takeWeekSpan() -> Int? {
        if takeAny(["a month", "one month", "en maned", "ein manad"], role: .number) != nil { return 4 }
        for index in words.indices where isFree(index...(index + 1)) {
            guard let value = RuleLexicon.number(words[index], allowAmbiguous: true) else { continue }
            if RuleLexicon.weekUnits.contains(words[index + 1]) {
                claim(index..<(index + 2), as: .number)
                return value
            }
            if RuleLexicon.monthUnits.contains(words[index + 1]) {
                claim(index..<(index + 2), as: .number)
                return value * 4
            }
        }
        if takeAny(["fortnight"], role: .number) != nil { return 2 }
        return nil
    }

    // MARK: - Plans, times and counts

    mutating func takeDinnerMode() -> DayDinnerMode? {
        if takeAny(RuleLexicon.takeaway, role: .food) != nil { return .takeaway }
        if takeAny(RuleLexicon.leftovers, role: .food) != nil { return .leftovers }
        if takeAny(RuleLexicon.away, role: .food) != nil { return .away }
        return nil
    }

    mutating func takeMinutes() -> Int? {
        if takeAny(RuleLexicon.halfHour, role: .number) != nil { return 30 }
        if takeAny(RuleLexicon.oneHour, role: .number) != nil { return 60 }
        for index in words.indices where isFree(index...(index + 1)) {
            guard let value = RuleLexicon.number(words[index], allowAmbiguous: true) else { continue }
            let unit = words[index + 1]
            let minutes: Int
            if RuleLexicon.minuteUnits.contains(unit) { minutes = value }
            else if RuleLexicon.hourUnits.contains(unit) { minutes = value * 60 }
            else { continue }
            claim(index..<(index + 2), as: .number)
            return minutes
        }
        return nil
    }

    mutating func takeBound() -> (kind: BoundKind, range: Range<Int>)? {
        if let range = takeAny(RuleLexicon.atMost) { return (kind: .atMost, range: range) }
        if let range = takeAny(RuleLexicon.atLeast) { return (kind: .atLeast, range: range) }
        if let range = takeAny(RuleLexicon.below) { return (kind: .below, range: range) }
        if let range = takeAny(RuleLexicon.above) {
            // "Ikke pasta mer enn to ganger": a negation ahead of "more than" makes it a limit.
            if let negation = words.indices.first(where: { $0 < range.lowerBound && !used.contains($0)
                && RuleLexicon.negationWords.contains(words[$0]) }) {
                claim(negation, as: .modifier)
                return (kind: .atMost, range: range)
            }
            return (kind: .above, range: range)
        }
        return nil
    }

    /// A number of dinners. "En" and "to" are also an article and a preposition, so they only
    /// count straight after a limit or in front of "ganger"/"times".
    mutating func takeCount(after bound: Range<Int>?, contextual: Bool) -> Int? {
        if takeAny(["once", "one time", "en gang", "ei gang", "ein gong"], role: .number) != nil { return 1 }
        if takeAny(["twice", "two times", "to ganger", "to gonger"], role: .number) != nil { return 2 }
        if takeAny(["thrice", "three times", "tre ganger"], role: .number) != nil { return 3 }
        for index in words.indices where !used.contains(index) {
            let next: String? = index + 1 < words.count && !used.contains(index + 1) ? words[index + 1] : nil
            let followedByTimes = next.map { RuleLexicon.times.contains($0) } ?? false
            guard contextual || followedByTimes else { continue }
            let rightAfterBound = bound?.upperBound == index
            guard let value = RuleLexicon.number(words[index], allowAmbiguous: followedByTimes || rightAfterBound) else { continue }
            claim(index, as: .number)
            if followedByTimes { claim(index + 1, as: .number) }
            return value
        }
        return nil
    }

    // MARK: - What the rule is about

    /// Every food the sentence names, in the order it names them.
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    mutating func takeFoods(meals: [Meal], customTags: [String]) -> [RuleSentenceParser.Food] {
        typealias Food = RuleSentenceParser.Food
        var found: [(position: Int, food: Food)] = []
        let mealNames = meals.map { meal in (meal: meal, words: RuleSentenceParser.tokenize(meal.name).map(RuleSentenceParser.fold)) }

        /// The one dish whose name contains any of `needles`, when there is exactly one.
        func uniqueMeal(named needles: [String]) -> Meal? {
            let hits = meals.filter { IngredientVocabulary.text($0.name, containsAnyOf: needles) }
            return hits.count == 1 ? hits[0] : nil
        }

        // 1. A dish named in full wins over the categories inside its name: "fish tacos".
        let named = mealNames
            .filter { $0.words.count >= 2 }
            .sorted { $0.words.count > $1.words.count }
        for candidate in named {
            guard let range = find(candidate.words.joined(separator: " ")) else { continue }
            claim(range, as: .food)
            found.append((position: range.lowerBound, food: Food(word: typedText(range), matcher: .exactMeal(candidate.meal.id))))
        }

        // 2. Categories. Parts of one compound read as one food, named by its last part the way
        //    Norwegian names it: "kyllingsuppe" is a soup, with chicken as the other reading.
        var hits: [(tag: MealTag, range: Range<Int>)] = []
        /// Which entry of `found` a compound became, so its other parts join it.
        var compoundFoods: [Int: Int] = [:]
        for entry in RuleLexicon.tags {
            while let range = takeAny(entry.phrases, role: .food) { hits.append((tag: entry.tag, range: range)) }
        }
        let bySource = Dictionary(grouping: hits, by: { source[$0.range.lowerBound] })
        for (origin, group) in bySource {
            let ordered = group.sorted { $0.range.lowerBound < $1.range.lowerBound }
            let isCompound = source.filter { $0 == origin }.count > 1
            let word = typed[origin]
            let head = ordered.last!
            let primaryTag = isCompound && RuleLexicon.dishForms.contains(head.tag) ? head.tag
                : (ordered.first { !RuleLexicon.modifierTags.contains($0.tag) } ?? ordered[0]).tag
            var alternatives: [MealMatcher] = ordered.map { $0.tag }.filter { $0 != primaryTag }.map { MealMatcher.tag($0) }
            var matcher = MealMatcher.tag(primaryTag)
            if isCompound, let dish = uniqueMeal(named: [RuleSentenceParser.fold(word)]) {
                alternatives.insert(matcher, at: 0)
                matcher = .exactMeal(dish.id)
            }
            if ordered.count == 1 || isCompound {
                if isCompound { compoundFoods[origin] = found.count }
                found.append((position: ordered[0].range.lowerBound, food: Food(word: isCompound ? word : typedText(ordered[0].range), matcher: matcher, alternatives: alternatives)))
            } else {
                // Two separate category words that only share a typed source by accident
                // cannot happen; separate words each get their own entry.
                for hit in ordered {
                    found.append((position: hit.range.lowerBound, food: Food(word: typedText(hit.range), matcher: .tag(hit.tag))))
                }
            }
        }
        // The dish word in "kyllinggryte" belongs to the chicken it was glued to.
        for index in words.indices where !used.contains(index) && RuleLexicon.dishNouns.contains(words[index]) {
            if source.indices.contains(where: { $0 != index && source[$0] == source[index] && used.contains($0) }) {
                claim(index, as: .food)
            }
        }

        // 3. Foods the vocabulary knows: "laks", "svinekjøtt", "nøtter".
        for index in words.indices where !used.contains(index) {
            guard let entry = IngredientVocabulary.entry(forFolded: words[index]) else { continue }
            claim(index, as: .food)
            let word = IngredientVocabulary.displayWord(for: entry, typedFolded: words[index])
            // "tomatsuppe" is a soup; the tomato is another way to read it, not a second food.
            if let compound = compoundFoods[source[index]] {
                found[compound].food.alternatives.append(.ingredient(word))
                continue
            }
            var alternatives: [MealMatcher] = []
            if let category = entry.category { alternatives.append(.tag(category)) }
            if let dish = uniqueMeal(named: entry.needles) { alternatives.append(.exactMeal(dish.id)) }
            found.append((position: index, food: Food(word: word, matcher: .ingredient(word), alternatives: alternatives)))
        }

        // 4. Labels the household invented.
        for label in customTags {
            let folded = RuleSentenceParser.tokenize(label).map(RuleSentenceParser.fold).joined(separator: " ")
            guard !folded.isEmpty, let range = takeAny([folded], role: .food) else { continue }
            found.append((position: range.lowerBound, food: Food(word: label, matcher: .customTag(label))))
        }

        // 5. One-word dish names: "lasagne", "carbonara".
        for candidate in mealNames where candidate.words.count == 1 && candidate.words[0].count >= 4 {
            guard let range = takeAny(candidate.words, role: .food) else { continue }
            found.append((position: range.lowerBound, food: Food(word: typedText(range), matcher: .exactMeal(candidate.meal.id))))
        }

        // 6. Only when nothing else named a food, whatever word is left: a word from one dish's
        //    name ("bolognese") is that dish, anything else is an ingredient ("no peanut butter",
        //    "grøt på lørdag"). Once a food is named, a leftover word is reported as not
        //    understood rather than turned into a second food: "taco på fredag hurra".
        guard found.isEmpty else { return Self.ordered(found) }
        var run: [Int] = []
        func closeRun() {
            defer { run = [] }
            guard !run.isEmpty, run.count <= 3 else { return }
            let range = run[0]..<(run[run.count - 1] + 1)
            let word = run.map { original[$0] }.joined(separator: " ")
            let folded = run.map { words[$0] }.joined(separator: " ")
            claim(range, as: .food)
            if run.count == 1, folded.count >= 5, let dish = uniqueMeal(named: [folded]) {
                found.append((position: run[0], food: Food(word: word, matcher: .exactMeal(dish.id), alternatives: [.ingredient(word)])))
            } else {
                found.append((position: run[0], food: Food(word: word, matcher: .ingredient(word))))
            }
        }
        for index in words.indices {
            let isContent = !used.contains(index) && !RuleLexicon.isFiller(words[index])
                && RuleLexicon.number(words[index], allowAmbiguous: true) == nil
            if isContent, run.last.map({ $0 == index - 1 }) ?? true {
                run.append(index)
            } else {
                closeRun()
                if isContent { run.append(index) }
            }
        }
        closeRun()
        return Self.ordered(found)
    }

    /// Foods in the order the sentence names them. "Quick fish" is about fish: a describing
    /// word yields when anything else is named.
    private static func ordered(_ found: [(position: Int, food: RuleSentenceParser.Food)]) -> [RuleSentenceParser.Food] {
        let ordered = found.sorted { $0.position < $1.position }.map { $0.food }
        let describing: (RuleSentenceParser.Food) -> Bool = { food in
            if case .tag(let tag) = food.matcher { return RuleLexicon.modifierTags.contains(tag) }
            return false
        }
        if ordered.contains(where: { !describing($0) }) {
            return ordered.filter { !describing($0) }
        }
        return ordered
    }
}

/// Every word the parser knows, folded: lowercase, no accents, æ/ø/å spelled out.
private enum RuleLexicon {
    static let tags: [(tag: MealTag, phrases: [String])] = [
        (tag: .fish, phrases: ["fish", "fishes", "seafood", "sea food", "fisk", "fisken", "fiske", "fiskemiddag",
                 "fiskemat", "fiskerett", "fiskeretter", "fiskedag", "sjomat", "fiskemiddager"]),
        (tag: .chicken, phrases: ["chicken", "chickens", "poultry", "kylling", "kyllingen", "kyllingmiddag",
                    "kyllingrett", "fjaerkre", "kyllingretter"]),
        (tag: .vegetarian, phrases: ["vegetarian", "veggie", "veggies", "meatless", "plant based", "plant - based",
                       "vegan", "vegetar", "vegetarisk", "vegetarmat", "vegetarmiddag", "vego",
                       "plantebasert", "kjottfri", "kjottfritt", "kjottfrie", "vegetarretter", "vegetarrett",
                       "vegetariske", "grønnsaksmiddag"]),
        (tag: .meat, phrases: ["red meat", "meat", "meats", "kjott", "rodt kjott", "kjottmiddag", "kjottrett", "kjottet",
                 "kjottretter"]),
        (tag: .pizza, phrases: ["pizza", "pizzas", "pizzaer", "pizzakveld", "pizzadag", "pizzaen"]),
        (tag: .pasta, phrases: ["pasta", "pastas", "spaghetti", "pastarett", "pastaretter", "pastamiddag", "pastaen"]),
        (tag: .soup, phrases: ["soup", "soups", "suppe", "supper", "suppemiddag", "suppen", "suppa"]),
        (tag: .taco, phrases: ["taco", "tacos", "tacokveld", "tacodag", "mexican", "meksikansk", "tacoen"]),
        (tag: .healthy, phrases: ["healthy", "healthier", "light", "lighter", "nutritious", "wholesome", "sunn",
                    "sunne", "sunt", "sunnere", "sunnmat", "lett", "lettere", "naeringsrik"]),
        (tag: .quick, phrases: ["quick", "fast", "speedy", "rask", "raske", "raskt", "kjapp", "kjappe", "kjapt",
                  "lettvint"]),
        (tag: .weekend, phrases: ["treat", "treats", "fancy", "kos", "kosemat", "helgemat", "helgekos"])
    ]

    /// Describe a dinner rather than name one, so they yield to a dish or a protein.
    static let modifierTags: Set<MealTag> = [.quick, .healthy, .weekend]

    /// The tags that name what a dish is, rather than what is in it. In a compound the last
    /// part names the dish: "fisketaco" is a taco, "kyllingsuppe" a soup.
    static let dishForms: Set<MealTag> = [.pizza, .pasta, .soup, .taco]

    /// Words that only say what kind of dish: they glue onto a food ("kyllinggryte") and say
    /// nothing a rule can use on their own.
    static let dishNouns: Set<String> = ["gryte", "gryterett", "grateng", "salat", "wok", "pai", "form", "panne",
                                         "boller", "kaker", "kake", "wrap", "wraps", "bowl", "curry", "middag",
                                         "rett", "retter", "burger", "burgere", "filet", "fileter"]

    static let meatFree = ["meat free", "meat - free", "meatfree", "kjottfri", "kjottfritt", "kjottfrie"]
    /// "-fri" glued onto a food: "glutenfri", "nøttefritt", "laktosefrie".
    static let freeSuffixes = ["fritt", "frie", "fri", "free"]

    static let everyDay = ["every day", "everyday", "each day", "daily", "every night", "every evening",
                           "all week", "hver dag", "hver kveld", "alle dager", "daglig", "hele uka", "hele uken"]
    static let weekdays = ["weekdays", "weekday", "week days", "weeknights", "weeknight", "week nights",
                           "school nights", "school night", "hverdager", "hverdagene", "hverdag",
                           "hverdagen", "hverdags", "ukedager", "ukedagene"]
    static let weekend = ["weekends", "weekend", "helgen", "helg", "helgene", "helger", "helga"]
    static let rangeConnectors: Set<String> = ["-", "to", "til", "through", "thru", "until", "till"]

    static let every: Set<String> = ["every", "each", "hver", "hvert", "kvar"]
    static let weekUnits: Set<String> = ["week", "weeks", "wk", "wks", "uke", "uker", "uka", "veke", "veker"]
    static let monthUnits: Set<String> = ["month", "months", "maned", "maneder", "manad", "manader"]
    static let everyOtherWeek = ["every other week", "every second week", "every 2 nd week", "every other",
                                 "every second", "fortnightly", "every fortnight", "annenhver uke",
                                 "annenhver", "annen hver uke", "hver annen uke", "hver andre uke", "annakvar",
                                 "hver andre", "hver annen"]
    static let everyThirdWeek = ["every third week", "every 3 rd week", "hver tredje uke", "hver tredje"]
    static let everyFourthWeek = ["every fourth week", "every 4 th week", "hver fjerde uke", "hver fjerde"]

    static let takeaway = ["takeaway", "take away", "take - away", "takeout", "take out", "take - out",
                           "order in", "order food", "delivery", "bestille mat", "bestiller mat",
                           "hente mat", "henter mat", "foodora", "wolt"]
    static let leftovers = ["leftovers", "leftover", "left overs", "left - overs", "rester", "restemat",
                            "restefest", "restedag"]
    static let away = ["eat out", "eating out", "dine out", "dining out", "out to eat", "restaurant",
                       "nobody home", "nobody is home", "no one home", "no one is home", "not home",
                       "not at home", "away", "no dinner", "skip dinner", "spise ute", "spiser ute",
                       "ute", "ingen hjemme", "ikke hjemme", "borte", "ingen middag"]

    static let halfHour = ["half an hour", "half hour", "halvtime", "en halvtime", "halvtimen"]
    static let oneHour = ["an hour", "one hour", "en time", "en times"]
    static let minuteUnits: Set<String> = ["min", "mins", "minute", "minutes", "minutt", "minutter", "minuttar"]
    static let hourUnits: Set<String> = ["hour", "hours", "hr", "hrs", "timer"]

    static let atMost = ["at most", "no more than", "not more than", "up to", "max", "maximum", "maks",
                         "maksimalt", "maksimum", "hoyst", "ikke mer enn", "ikke flere enn", "opptil",
                         "inntil", "limit", "limited to", "begrens", "begrenset til"]
    static let atLeast = ["at least", "minimum", "no fewer than", "no less than", "not less than", "minst",
                          "i hvert fall", "iallfall", "iallefall"]
    static let below = ["less than", "fewer than", "under", "mindre enn", "faerre enn"]
    static let above = ["more than", "mer enn", "flere enn", "over enn"]

    static let negation = ["never", "no", "not", "dont", "avoid", "without", "skip", "exclude", "free",
                           "aldri", "ingen", "ikke", "uten", "unnga", "unngar", "dropp", "slutt med"]
    /// Single negating words, for a negation that sits apart from the limit it turns around.
    static let negationWords: Set<String> = ["never", "no", "not", "dont", "aldri", "ingen", "ikke"]
    static let dislike = ["liker ikke", "like ikke", "doesnt like", "does not like", "dont like", "do not like",
                          "hater", "hates", "dislikes", "dislike", "spiser ikke", "wont eat", "will not eat",
                          "vil ikke ha", "vil ikke spise", "orker ikke", "takler ikke", "taler ikke"]
    static let allergy = ["allergic to", "allergic", "allergy", "allergies", "intolerant to", "intolerant",
                          "allergi", "allergisk mot", "allergisk", "intoleranse"]
    static let consecutive = ["two days in a row", "2 days in a row", "days in a row", "nights in a row",
                              "in a row", "two days running", "2 days running", "days running",
                              "back to back", "back - to - back", "consecutive days", "consecutive nights",
                              "consecutive", "to dager pa rad", "2 dager pa rad", "dager pa rad", "pa rad",
                              "to dager etter hverandre", "etter hverandre"]
    static let repeats = ["no repeats", "repeats", "repeat", "repeating", "repetition", "repetitions",
                          "same dinner", "same meal", "same thing", "duplicates", "gjentakelser",
                          "gjentakelse", "gjentagelser", "gjenta", "samme middag", "samme rett", "samme mat"]
    static let weekly = ["a week", "per week", "each week", "every week", "weekly", "in a week", "a wk",
                         "per wk", "i uka", "i uken", "per uke", "pr uke", "hver uke", "i veka", "om uka",
                         "ukentlig", "i uke"]
    static let times: Set<String> = ["times", "time", "x", "ganger", "gang", "gonger"]

    static let preference = ["preferably", "ideally", "if possible", "when possible", "try to", "prefer",
                             "would like", "gjerne", "helst", "om mulig", "hvis mulig", "forsok a",
                             "prov a", "foretrekker"]
    static let only = ["only", "always", "exclusively", "nothing but", "kun", "bare", "alltid", "utelukkende"]

    private static let stopwords: Set<String> = [
        "-", "a", "an", "the", "on", "in", "at", "of", "for", "with", "and", "or", "we", "i", "us", "our",
        "my", "me", "eat", "eats", "eating", "have", "has", "having", "cook", "cooks", "cooking", "make",
        "makes", "making", "want", "wants", "like", "likes", "dinner", "dinners", "supper", "suppers",
        "meal", "meals", "food", "foods", "dish", "dishes", "night", "nights", "evening", "evenings",
        "is", "are", "be", "should", "must", "need", "needs", "please", "some", "any", "it", "its",
        "lets", "let", "do", "does", "per", "week", "weeks", "wk", "wks", "weekly", "each", "every",
        "than", "most", "least", "more", "less", "fewer", "within", "day", "days", "x", "times", "time",
        "to", "until", "through", "as", "just", "get", "serve", "served", "that", "this", "all", "also",
        "by", "from", "over", "up", "out", "but", "so", "there", "then", "can", "will", "would", "shall",
        "family", "kids", "rule", "home", "one", "lunch", "something", "new", "different", "when", "if",
        "cold", "warm", "hot", "cheap", "cheaper", "end", "month", "kind", "type", "nice", "good",
        "pa", "om", "vi", "jeg", "oss", "var", "vare", "skal", "har", "ha", "spiser", "spise", "spis",
        "lager", "lage", "lag", "middag", "middager", "middagen", "kveld", "kvelder", "kvelden", "mat",
        "maten", "retter", "rett", "retten", "en", "et", "ett", "ei", "uka", "uke", "uken", "uker",
        "per", "pr", "hver", "hvert", "gang", "ganger", "dag", "dager", "dagen", "og", "eller", "med",
        "til", "for", "av", "ma", "bor", "vil", "noe", "noen", "som", "det", "den", "de", "er", "alle",
        "hele", "mer", "enn", "fra", "etter", "over", "da", "sa", "ogsa", "regel", "familien", "hjemme",
        "barna", "gjerne", "men", "nytt", "ny", "nye", "annet", "forskjellig", "variert", "variasjon",
        "nar", "hvis", "kaldt", "varmt", "billig", "billigere", "mot", "slutten", "maneden", "starten",
        "god", "godt", "deilig", "ungene", "barn", "meg", "deg", "seg", "dem", "denne", "dette", "disse",
        "litt", "mye", "gjor", "blir", "bli", "pa", "inn", "ut"
    ]

    /// A word that carries no meaning for a rule on its own.
    static func isFiller(_ word: String) -> Bool { stopwords.contains(word) }

    static func weekday(_ word: String) -> Weekday? { weekdayForms[word] }

    /// A day name with one letter wrong, added, dropped or swapped: "torsdg", "fredga".
    static func nearWeekday(_ word: String) -> Weekday? {
        guard word.count >= 5, !isKnown(word), IngredientVocabulary.entry(forFolded: word) == nil else { return nil }
        var best: Weekday?
        for (form, day) in weekdayForms where form.count >= 5 && form.first == word.first {
            guard editDistance(form, word, limit: 1) <= 1 else { continue }
            if let existing = best, existing != day { return nil }
            best = day
        }
        return best
    }

    private static let weekdayForms: [String: Weekday] = {
        var forms: [String: Weekday] = [:]
        let english: [(Weekday, [String])] = [
            (.monday, ["monday", "mon"]), (.tuesday, ["tuesday", "tue", "tues"]),
            (.wednesday, ["wednesday", "wed"]), (.thursday, ["thursday", "thu", "thur", "thurs"]),
            (.friday, ["friday", "fri"]), (.saturday, ["saturday", "sat"]), (.sunday, ["sunday", "sun"])
        ]
        for (day, names) in english {
            for name in names {
                forms[name] = day
                forms[name + "s"] = day
            }
        }
        for (day, stem) in norwegianStems {
            for suffix in ["", "en", "er", "ene", "s"] { forms[stem + suffix] = day }
        }
        return forms
    }()

    private static let norwegianStems: [(Weekday, String)] = [
        (.monday, "mandag"), (.tuesday, "tirsdag"), (.wednesday, "onsdag"), (.thursday, "torsdag"),
        (.friday, "fredag"), (.saturday, "lordag"), (.sunday, "sondag")
    ]

    /// Longest first, so "fredags" is tried before "fredag".
    static let compoundDayStems: [String] = norwegianStems
        .flatMap { [$0.1 + "s", $0.1] }
        .sorted { $0.count > $1.count }

    private static let tagWords: Set<String> = {
        var words = Set<String>()
        for entry in tags {
            for phrase in entry.phrases where !phrase.contains(" ") { words.insert(phrase) }
        }
        return words
    }()

    /// Single words that can stand on their own after a compound is split.
    private static let knownWords: Set<String> = {
        var words = stopwords.union(tagWords)
        for phrase in takeaway + leftovers + meatFree where !phrase.contains(" ") { words.insert(phrase) }
        return words
    }()

    static func isKnown(_ word: String) -> Bool { knownWords.contains(word) }

    /// Every word of every phrase the grammar reads. Never "corrected" into a food: "uten",
    /// "maks" and "bare" mean what they say.
    private static let lexiconWords: Set<String> = {
        // One flatMap over a typed array: a 24-term chain of + can exceed the type checker's budget.
        let lists: [[String]] = [everyDay, weekdays, weekend, everyOtherWeek, everyThirdWeek, everyFourthWeek,
                                 takeaway, leftovers, away, halfHour, oneHour, atMost, atLeast, below, above,
                                 negation, dislike, allergy, consecutive, repeats, weekly, preference, only, meatFree]
        let phrases = lists.flatMap { $0 }
        var words = knownWords.union(rangeConnectors).union(every).union(weekUnits).union(monthUnits)
            .union(minuteUnits).union(hourUnits).union(times).union(negationWords).union(dishNouns)
        for phrase in phrases {
            for part in phrase.split(separator: " ") { words.insert(String(part)) }
        }
        return words
    }()

    /// A category word or a food the vocabulary knows.
    static func isFoodWord(_ word: String) -> Bool {
        tagWords.contains(word) || IngredientVocabulary.entry(forFolded: word) != nil
    }

    /// The word a household meant, when it typed an inflected or slightly misspelt food:
    /// "tacoen" → "taco", "suppa" → "suppe", "pizzae" → "pizza". Anything else is left as typed.
    static func lemma(_ word: String) -> String {
        guard !isKnown(word), !lexiconWords.contains(word), weekday(word) == nil, IngredientVocabulary.entry(forFolded: word) == nil,
              number(word, allowAmbiguous: true) == nil else { return word }
        for suffix in ["ene", "ane", "er", "en", "et", "a", "e"] where word.hasSuffix(suffix) && word.count - suffix.count >= 3 {
            let stem = String(word.dropLast(suffix.count))
            for candidate in [stem, stem + "e", stem + "a"] where isFoodWord(candidate) { return candidate }
        }
        // One letter off a known food: "tako", "piza". Only for words long enough to be sure.
        guard word.count >= 4 else { return word }
        var best: String?
        for candidate in tagWords.union(IngredientVocabulary.entries.flatMap(\.forms))
        where candidate.count >= 4 && candidate.first == word.first && abs(candidate.count - word.count) <= 1 {
            guard editDistance(candidate, word, limit: 1) <= 1 else { continue }
            if best != nil { return word }
            best = candidate
        }
        return best ?? word
    }

    /// Levenshtein distance with adjacent swaps counted once, stopping early past `limit`.
    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let left = Array(a), right = Array(b)
        if abs(left.count - right.count) > limit { return limit + 1 }
        var previousPrevious = [Int](repeating: 0, count: right.count + 1)
        var previous = Array(0...right.count)
        for i in 1...max(left.count, 1) where !left.isEmpty {
            var current = [Int](repeating: 0, count: right.count + 1)
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...max(right.count, 1) where !right.isEmpty {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, left[i - 1] == right[j - 2], left[i - 2] == right[j - 1] {
                    current[j] = min(current[j], previousPrevious[j - 2] + 1)
                }
                rowMinimum = min(rowMinimum, current[j])
            }
            if rowMinimum > limit { return limit + 1 }
            previousPrevious = previous
            previous = current
        }
        return left.isEmpty ? right.count : previous[right.count]
    }

    /// Monday-first, wrapping: "friday to monday" is the long weekend.
    static func days(from first: Weekday, through last: Weekday) -> Set<Weekday> {
        let all = Weekday.allCases
        guard let start = all.firstIndex(of: first), let end = all.firstIndex(of: last) else { return [first, last] }
        if start <= end { return Set(all[start...end]) }
        return Set(all[start...]).union(all[...end])
    }

    private static let unambiguousNumbers: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "null": 0, "tre": 3, "fire": 4, "fem": 5, "seks": 6, "sju": 7, "syv": 7
    ]
    private static let ambiguousNumbers: [String: Int] = ["en": 1, "ett": 1, "ei": 1, "ein": 1, "eitt": 1, "to": 2]

    static func number(_ word: String, allowAmbiguous: Bool) -> Int? {
        if let value = Int(word) { return (0...500).contains(value) ? value : nil }
        if let value = unambiguousNumbers[word] { return value }
        return allowAmbiguous ? ambiguousNumbers[word] : nil
    }
}
