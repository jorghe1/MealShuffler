import Foundation

enum L10n {
    static func portions(_ value: Double) -> String {
        value == 1 ? string("1 serving") : string("%@ servings", value.formatted(.number.precision(.fractionLength(0...2))))
    }
    private static let singularForms: [String: (Int, String)] = [
        "%ld servings": (0, "%ld serving"),
        "%ld minutes": (0, "%ld minute"),
        "%ld people": (0, "%ld person"),
        "%ld people eating": (0, "%ld person eating"),
        "%ld people at dinner": (0, "%ld person at dinner"),
        "About %ld minutes": (0, "About %ld minute"),
        "Maximum %ld minutes": (0, "Maximum %ld minute"),
        "Every %ld weeks": (0, "Every %ld week"),
        "%ld meals": (0, "%ld meal"),
        "%ld dinners ready to take over": (0, "%ld dinner ready to take over"),
        "Cooked %ld times": (0, "Cooked %ld time"),
        "Shuffle %ld remaining dinners": (0, "Shuffle %ld remaining dinner"),
        "%ld shared recipes": (0, "%ld shared recipe"),
        "We cook %@ at least %ld times per week.": (1, "We cook %@ at least %ld time per week."),
        "We cook %@ at most %ld times per week.": (1, "We cook %@ at most %ld time per week."),
        "Dinner takes at most %ld minutes %@.": (0, "Dinner takes at most %ld minute %@."),
        "We cook %@ at least once every %ld weeks.": (1, "We cook %@ at least once every %ld week."),
        "Ingredients for %ld planned dinners": (0, "Ingredients for %ld planned dinner"),
        "%@ at least every %ld weeks": (1, "%@ at least every %ld week")
    ]
    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        var selectedKey = key
        if let (index, singular) = singularForms[key], arguments.indices.contains(index), arguments[index] as? Int == 1 { selectedKey = singular }
        if ["%ld min · %ld servings", "%ld minutes · %ld servings"].contains(key), arguments.count == 2,
           let minutes = arguments[0] as? Int, let portions = arguments[1] as? Int {
            return string("%ld min", minutes) + " · " + Self.portions(Double(portions))
        }
        let format = Bundle.main.localizedString(forKey: selectedKey, value: selectedKey, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: .current, arguments: arguments)
    }
}
