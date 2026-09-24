import Foundation

/// Reads a rule the way a household says it.
///
/// "Taco Friday", "fredagstaco", "max two chicken a week", "no pasta on weekdays". The
/// template builder can express every one of these, but it takes five taps and a mental
/// translation into its vocabulary, and a rule is the thing people most want to state in one
/// breath. This does the translation.
///
/// Deliberately a small, deterministic grammar rather than a model call: it works offline,
/// answers on every keystroke, and whatever it produces is shown back as the rule's own
/// sentence before anything is saved -- so a misreading is visible, never silent. English and
/// Norwegian Bokmål are read regardless of the device language, because a household types in
/// whichever it thinks in.
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
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Outcome {
        var sentence = RuleSentence(text)
        guard sentence.hasContent else { return .notUnderstood }

        let preferred = sentence.takeAny(RuleLexicon.preference) != nil
        let only = sentence.takeAny(RuleLexicon.only) != nil
        let interval = sentence.takeInterval()
        let scope = sentence.takeScope()

        func make(_ constraint: RuleConstraint, schedule: Int? = nil) -> Outcome {
            var rule = PlanningRule(
                title: title(for: text),
                strength: preferred ? .preferred : .required,
                constraint: constraint
            )
            if let schedule, schedule > 1 {
                rule.repeatEveryWeeks = min(schedule, 8)
                rule.firstWeek = WeekAnchor.startOfWeek(containing: now, calendar: calendar)
            }
            return .rule(rule)
        }

        // Day plans first: "no dinner" and "nobody home" carry a negation that belongs to them.
        if let mode = sentence.takeDinnerMode() {
            if sentence.takeAny(RuleLexicon.negation) != nil {
                return .incomplete(hint: L10n.string("Day plans say what does happen, for example “takeaway on Friday”."))
            }
            guard let scope else { return .incomplete(hint: daysHint) }
            return make(.dinnerMode(day: scope, mode: mode), schedule: interval)
        }

        if sentence.takeAny(RuleLexicon.repeats) != nil {
            let weeks = sentence.takeWeekSpan() ?? 1
            return make(.noRepeatWithin(weeks: min(max(weeks, 1), 8)))
        }

        if let minutes = sentence.takeMinutes() {
            return make(.maximumPrepTime(day: scope ?? .everyDay, minutes: min(max(minutes, 5), 240)), schedule: interval)
        }

        // Before the negations, because "meat-free" is not "no meat": it means vegetarian.
        let meatFree = sentence.takeAny(RuleLexicon.meatFree) != nil
        let consecutive = sentence.takeAny(RuleLexicon.consecutive) != nil
        // Before the negations too: "no more than two" is a limit, not a ban.
        let bound = sentence.takeBound()
        let negated = sentence.takeAny(RuleLexicon.negation) != nil
        let allergy = sentence.takeAny(RuleLexicon.allergy) != nil
        let weekly = sentence.takeAny(RuleLexicon.weekly) != nil
        let count = sentence.takeCount(after: bound?.range, contextual: weekly || bound != nil)
        let matcher: MealMatcher? = meatFree
            ? MealMatcher.tag(.vegetarian)
            : sentence.takeMatcher(meals: meals, customTags: customTags)

        guard let matcher else {
            let understood = scope != nil || consecutive || bound != nil || negated || allergy
                || weekly || count != nil || only || interval != nil
            return understood ? .incomplete(hint: whatHint) : .notUnderstood
        }

        if consecutive { return make(.notOnConsecutiveDays(matcher: matcher)) }

        if negated || allergy {
            if let scope, scope != .everyDay {
                return make(.excludedOn(day: scope, matcher: matcher), schedule: interval)
            }
            return make(.maximumPerWeek(matcher: matcher, count: 0))
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
            case .atLeast, nil:
                return make(.minimumPerWeek(matcher: matcher, count: min(max(count, 1), 7)))
            }
        }
        if bound != nil { return .incomplete(hint: L10n.string("Add a number, for example “max 2 a week”.")) }

        if let scope { return make(.requiredOn(day: scope, matcher: matcher), schedule: interval) }
        if only { return make(.requiredOn(day: .everyDay, matcher: matcher)) }
        return .incomplete(hint: L10n.string("Add a day or a number, for example “on Fridays” or “twice a week”."))
    }

    /// Several rules in one line: "taco Friday, fish twice a week; no nuts".
    ///
    /// Split at commas, semicolons and line breaks -- but not at a comma inside a number, which
    /// is how Norwegian writes "1,5 time". "And" is not a separator: "fish on Tuesday and
    /// Thursday" is one rule.
    static func parseAll(
        _ text: String,
        meals: [Meal],
        customTags: [String] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(text: String, outcome: Outcome)] {
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
        let parts = pieces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.prefix(12).map { part in
            (text: part, outcome: parse(part, meals: meals, customTags: customTags, now: now, calendar: calendar))
        }
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

    /// Case, accents and the Nordic letters, which diacritic folding leaves alone because they
    /// are letters of their own rather than accented vowels.
    fileprivate static func fold(_ value: String) -> String {
        var folded = value.lowercased()
        for (letter, ascii) in [("æ", "ae"), ("ø", "o"), ("å", "a")] {
            folded = folded.replacingOccurrences(of: letter, with: ascii)
        }
        return folded.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
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

    /// Norwegian joins the day to the dish: "fredagstaco", "tacofredag", "søndagsmiddag".
    fileprivate static func splitCompound(_ word: String) -> [String]? {
        guard word.count >= 6, RuleLexicon.weekday(word) == nil, !RuleLexicon.isKnown(word) else { return nil }
        for stem in RuleLexicon.compoundDayStems {
            if word.hasPrefix(stem) {
                let rest = String(word.dropFirst(stem.count))
                if RuleLexicon.isKnown(rest) { return [stem, rest] }
            }
            if word.hasSuffix(stem) {
                let rest = String(word.dropLast(stem.count))
                if RuleLexicon.isKnown(rest) { return [rest, stem] }
            }
        }
        return nil
    }
}

/// The typed sentence, with a record of which words have been accounted for.
///
/// Each reading step claims the words it understood, so later steps cannot read them twice:
/// the "two" in "two days in a row" is not also a weekly count.
private struct RuleSentence {
    enum BoundKind { case atMost, atLeast, below }

    private(set) var words: [String] = []
    private(set) var original: [String] = []
    private var used: Set<Int> = []

    init(_ text: String) {
        for piece in RuleSentenceParser.tokenize(text) {
            let folded = RuleSentenceParser.fold(piece)
            if let parts = RuleSentenceParser.splitCompound(folded) {
                words += parts
                original += parts
            } else {
                words.append(folded)
                original.append(piece)
            }
        }
    }

    var hasContent: Bool { words.contains { $0 != "-" } }

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

    /// Claims the longest matching phrase.
    mutating func takeAny(_ phrases: [String]) -> Range<Int>? {
        let longestFirst = phrases.sorted { $0.split(separator: " ").count > $1.split(separator: " ").count }
        for phrase in longestFirst {
            if let range = find(phrase) {
                used.formUnion(range)
                return range
            }
        }
        return nil
    }

    private func isFree(_ indices: ClosedRange<Int>) -> Bool {
        indices.upperBound < words.count && indices.allSatisfy { !used.contains($0) }
    }

    // MARK: - Days

    mutating func takeScope() -> DayScope? {
        var group: DayScope?
        if takeAny(RuleLexicon.everyDay) != nil { group = .everyDay }
        else if takeAny(RuleLexicon.weekdays) != nil { group = .weekdays }
        else if takeAny(RuleLexicon.weekend) != nil { group = .weekend }

        var days: Set<Weekday> = []
        var index = 0
        while index + 2 < words.count {
            if isFree(index...(index + 2)),
               let first = RuleLexicon.weekday(words[index]),
               RuleLexicon.rangeConnectors.contains(words[index + 1]),
               let last = RuleLexicon.weekday(words[index + 2]) {
                days.formUnion(RuleLexicon.days(from: first, through: last))
                used.formUnion(index...(index + 2))
                index += 3
            } else {
                index += 1
            }
        }
        for position in words.indices where !used.contains(position) {
            if let day = RuleLexicon.weekday(words[position]) {
                days.insert(day)
                used.insert(position)
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

    /// "Every other week", "every 3 weeks", "annenhver uke", "hver 3. uke".
    mutating func takeInterval() -> Int? {
        if takeAny(RuleLexicon.everyOtherWeek) != nil { return 2 }
        if takeAny(RuleLexicon.everyThirdWeek) != nil { return 3 }
        if takeAny(RuleLexicon.everyFourthWeek) != nil { return 4 }
        for index in words.indices where isFree(index...(index + 2)) {
            guard RuleLexicon.every.contains(words[index]),
                  let value = Int(words[index + 1]), (1...8).contains(value),
                  RuleLexicon.weekUnits.contains(words[index + 2]) else { continue }
            used.formUnion(index...(index + 2))
            return value
        }
        return nil
    }

    /// "Within 3 weeks", "for a month".
    mutating func takeWeekSpan() -> Int? {
        if takeAny(["a month", "one month", "en maned", "ein manad"]) != nil { return 4 }
        for index in words.indices where isFree(index...(index + 1)) {
            guard let value = RuleLexicon.number(words[index], allowAmbiguous: true) else { continue }
            if RuleLexicon.weekUnits.contains(words[index + 1]) {
                used.formUnion(index...(index + 1))
                return value
            }
            if RuleLexicon.monthUnits.contains(words[index + 1]) {
                used.formUnion(index...(index + 1))
                return value * 4
            }
        }
        if takeAny(["fortnight"]) != nil { return 2 }
        return nil
    }

    // MARK: - Plans, times and counts

    mutating func takeDinnerMode() -> DayDinnerMode? {
        if takeAny(RuleLexicon.takeaway) != nil { return .takeaway }
        if takeAny(RuleLexicon.leftovers) != nil { return .leftovers }
        if takeAny(RuleLexicon.away) != nil { return .away }
        return nil
    }

    mutating func takeMinutes() -> Int? {
        if takeAny(RuleLexicon.halfHour) != nil { return 30 }
        if takeAny(RuleLexicon.oneHour) != nil { return 60 }
        for index in words.indices where isFree(index...(index + 1)) {
            guard let value = RuleLexicon.number(words[index], allowAmbiguous: true) else { continue }
            let unit = words[index + 1]
            let minutes: Int
            if RuleLexicon.minuteUnits.contains(unit) { minutes = value }
            else if RuleLexicon.hourUnits.contains(unit) { minutes = value * 60 }
            else { continue }
            used.formUnion(index...(index + 1))
            return minutes
        }
        return nil
    }

    mutating func takeBound() -> (kind: BoundKind, range: Range<Int>)? {
        if let range = takeAny(RuleLexicon.atMost) { return (kind: .atMost, range: range) }
        if let range = takeAny(RuleLexicon.atLeast) { return (kind: .atLeast, range: range) }
        if let range = takeAny(RuleLexicon.below) { return (kind: .below, range: range) }
        return nil
    }

    /// A number of dinners. "En" and "to" are also an article and a preposition, so they only
    /// count straight after a limit or in front of "ganger"/"times".
    mutating func takeCount(after bound: Range<Int>?, contextual: Bool) -> Int? {
        if takeAny(["once", "one time", "en gang", "ei gang", "ein gong"]) != nil { return 1 }
        if takeAny(["twice", "two times", "to ganger", "to gonger"]) != nil { return 2 }
        if takeAny(["thrice", "three times", "tre ganger"]) != nil { return 3 }
        for index in words.indices where !used.contains(index) {
            let next: String? = index + 1 < words.count && !used.contains(index + 1) ? words[index + 1] : nil
            let followedByTimes = next.map { RuleLexicon.times.contains($0) } ?? false
            guard contextual || followedByTimes else { continue }
            let rightAfterBound = bound?.upperBound == index
            guard let value = RuleLexicon.number(words[index], allowAmbiguous: followedByTimes || rightAfterBound) else { continue }
            used.insert(index)
            if followedByTimes { used.insert(index + 1) }
            return value
        }
        return nil
    }

    // MARK: - What the rule is about

    mutating func takeMatcher(meals: [Meal], customTags: [String]) -> MealMatcher? {
        // A dish named in full wins over the categories inside its name: "fish tacos".
        var best: (id: UUID, length: Int, range: Range<Int>)?
        for meal in meals {
            let name = RuleSentenceParser.tokenize(meal.name).map(RuleSentenceParser.fold)
            guard name.count >= 2, let range = find(name.joined(separator: " ")) else { continue }
            if best.map({ name.count > $0.length }) ?? true { best = (id: meal.id, length: name.count, range: range) }
        }
        if let best {
            used.formUnion(best.range)
            return .exactMeal(best.id)
        }

        // Categories. Every one mentioned is claimed so none is mistaken for an ingredient,
        // and the dish or protein wins over a modifier: "quick fish" is about fish.
        var found: [(tag: MealTag, position: Int)] = []
        for entry in RuleLexicon.tags {
            while let range = takeAny(entry.phrases) { found.append((tag: entry.tag, position: range.lowerBound)) }
        }
        let ordered = found.sorted { $0.position < $1.position }
        if let chosen = ordered.first(where: { !RuleLexicon.modifierTags.contains($0.tag) }) ?? ordered.first {
            return .tag(chosen.tag)
        }

        for label in customTags {
            let folded = RuleSentenceParser.tokenize(label).map(RuleSentenceParser.fold).joined(separator: " ")
            if !folded.isEmpty, takeAny([folded]) != nil { return .customTag(label) }
        }

        for meal in meals {
            let name = RuleSentenceParser.tokenize(meal.name).map(RuleSentenceParser.fold)
            if name.count == 1, name[0].count >= 4, takeAny(name) != nil { return .exactMeal(meal.id) }
        }

        // Whatever food word is left is read as an ingredient: "no nuts", "salmon on Monday".
        let leftovers = words.indices.filter { index in
            !used.contains(index) && !RuleLexicon.stopwords.contains(words[index])
                && RuleLexicon.number(words[index], allowAmbiguous: true) == nil
        }
        guard let first = leftovers.first, let last = leftovers.last, leftovers.count <= 3,
              last - first == leftovers.count - 1 else { return nil }
        used.formUnion(leftovers)
        var name = leftovers.map { original[$0] }.joined(separator: " ")
        if leftovers.count == 1, name.count > 3 {
            if name.hasSuffix("oes") { name.removeLast(2) }
            else if name.hasSuffix("s"), !name.hasSuffix("ss"), !name.hasSuffix("ies") { name.removeLast() }
        }
        return .ingredient(name)
    }
}

/// Every word the parser knows, folded: lowercase, no accents, æ/ø/å spelled out.
private enum RuleLexicon {
    static let tags: [(tag: MealTag, phrases: [String])] = [
        (tag: .fish, phrases: ["fish", "fishes", "seafood", "sea food", "fisk", "fisken", "fiske", "fiskemiddag",
                 "fiskemat", "fiskerett", "fiskeretter", "fiskedag", "sjomat"]),
        (tag: .chicken, phrases: ["chicken", "chickens", "poultry", "kylling", "kyllingen", "kyllingmiddag",
                    "kyllingrett", "fjaerkre"]),
        (tag: .vegetarian, phrases: ["vegetarian", "veggie", "veggies", "meatless", "plant based", "plant - based",
                       "vegan", "vegetar", "vegetarisk", "vegetarmat", "vegetarmiddag", "vego",
                       "plantebasert", "kjottfri", "kjottfritt", "kjottfrie"]),
        (tag: .meat, phrases: ["red meat", "meat", "meats", "kjott", "rodt kjott", "kjottmiddag", "kjottrett"]),
        (tag: .pizza, phrases: ["pizza", "pizzas", "pizzaer", "pizzakveld", "pizzadag"]),
        (tag: .pasta, phrases: ["pasta", "pastas", "spaghetti", "pastarett", "pastaretter", "pastamiddag"]),
        (tag: .soup, phrases: ["soup", "soups", "suppe", "supper", "suppemiddag"]),
        (tag: .taco, phrases: ["taco", "tacos", "tacokveld", "tacodag", "mexican", "meksikansk"]),
        (tag: .healthy, phrases: ["healthy", "healthier", "light", "lighter", "nutritious", "wholesome", "sunn",
                    "sunne", "sunt", "sunnere", "sunnmat", "lett", "lettere", "naeringsrik"]),
        (tag: .quick, phrases: ["quick", "fast", "speedy", "rask", "raske", "raskt", "kjapp", "kjappe", "kjapt",
                  "lettvint"]),
        (tag: .weekend, phrases: ["treat", "treats", "fancy", "kos", "kosemat", "helgemat", "helgekos"])
    ]

    /// Describe a dinner rather than name one, so they yield to a dish or a protein.
    static let modifierTags: Set<MealTag> = [.quick, .healthy, .weekend]

    static let meatFree = ["meat free", "meat - free", "meatfree", "kjottfri", "kjottfritt", "kjottfrie"]

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
                                 "annenhver", "annen hver uke", "hver annen uke", "hver andre uke", "annakvar"]
    static let everyThirdWeek = ["every third week", "every 3 rd week", "hver tredje uke"]
    static let everyFourthWeek = ["every fourth week", "every 4 th week", "hver fjerde uke"]

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

    static let negation = ["never", "no", "not", "dont", "avoid", "without", "skip", "exclude", "free",
                           "aldri", "ingen", "ikke", "uten", "unnga", "unngar", "dropp", "slutt med"]
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

    static let stopwords: Set<String> = [
        "-", "a", "an", "the", "on", "in", "at", "of", "for", "with", "and", "or", "we", "i", "us", "our",
        "my", "me", "eat", "eats", "eating", "have", "has", "having", "cook", "cooks", "cooking", "make",
        "makes", "making", "want", "wants", "like", "likes", "dinner", "dinners", "supper", "suppers",
        "meal", "meals", "food", "foods", "dish", "dishes", "night", "nights", "evening", "evenings",
        "is", "are", "be", "should", "must", "need", "needs", "please", "some", "any", "it", "its",
        "lets", "let", "do", "does", "per", "week", "weeks", "wk", "wks", "weekly", "each", "every",
        "than", "most", "least", "more", "less", "fewer", "within", "day", "days", "x", "times", "time",
        "to", "until", "through", "as", "just", "get", "serve", "served", "that", "this", "all", "also",
        "by", "from", "over", "up", "out", "but", "so", "there", "then", "can", "will", "would", "shall",
        "family", "kids", "rule", "home", "one", "lunch",
        "pa", "om", "vi", "jeg", "oss", "var", "vare", "skal", "har", "ha", "spiser", "spise", "spis",
        "lager", "lage", "lag", "middag", "middager", "middagen", "kveld", "kvelder", "kvelden", "mat",
        "maten", "retter", "rett", "retten", "en", "et", "ett", "ei", "uka", "uke", "uken", "uker",
        "per", "pr", "hver", "hvert", "gang", "ganger", "dag", "dager", "dagen", "og", "eller", "med",
        "til", "for", "av", "ma", "bor", "vil", "noe", "noen", "som", "det", "den", "de", "er", "alle",
        "hele", "mer", "enn", "fra", "etter", "over", "da", "sa", "ogsa", "regel", "familien", "hjemme",
        "barna", "gjerne"
    ]

    static func weekday(_ word: String) -> Weekday? { weekdayForms[word] }

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

    /// Single words that can stand on their own after a compound is split.
    private static let knownWords: Set<String> = {
        var words = stopwords
        for entry in tags {
            for phrase in entry.phrases where !phrase.contains(" ") { words.insert(phrase) }
        }
        for phrase in takeaway + leftovers + meatFree where !phrase.contains(" ") { words.insert(phrase) }
        return words
    }()

    static func isKnown(_ word: String) -> Bool { knownWords.contains(word) }

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
