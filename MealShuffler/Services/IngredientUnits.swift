import Foundation

enum IngredientUnits {
    struct Normalized {
        let quantity: Double
        let unit: String
    }

    static func normalize(quantity: Double, unit: String) -> Normalized {
        switch unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "kg": Normalized(quantity: quantity * 1_000, unit: "g")
        case "l", "liter", "litre": Normalized(quantity: quantity * 1_000, unit: "ml")
        case "dl": Normalized(quantity: quantity * 100, unit: "ml")
        case "cl": Normalized(quantity: quantity * 10, unit: "ml")
        case "ss", "tbsp", "tablespoon", "tablespoons": Normalized(quantity: quantity * 15, unit: "ml")
        case "ts", "tsp", "teaspoon", "teaspoons": Normalized(quantity: quantity * 5, unit: "ml")
        case "stk", "piece", "pieces", "pc", "pcs": Normalized(quantity: quantity, unit: "pcs")
        case "beger", "tub", "tubs": Normalized(quantity: quantity, unit: "tub")
        case "pose", "bag", "bags": Normalized(quantity: quantity, unit: "bag")
        case "flaske", "bottle", "bottles": Normalized(quantity: quantity, unit: "bottle")
        case "glass", "jar", "jars": Normalized(quantity: quantity, unit: "jar")
        case "boks", "can", "cans", "tin", "tins": Normalized(quantity: quantity, unit: "can")
        case "potte", "pot", "pots": Normalized(quantity: quantity, unit: "pot")
        default: Normalized(quantity: quantity, unit: unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func display(quantity: Double, unit: String) -> String {
        var value = quantity
        var displayUnit = unit
        if unit == "g", quantity >= 1_000 {
            value = quantity / 1_000
            displayUnit = "kg"
        } else if unit == "ml", quantity >= 1_000 {
            value = quantity / 1_000
            displayUnit = "l"
        } else if unit == "ml", quantity >= 100, quantity.truncatingRemainder(dividingBy: 100) == 0 {
            value = quantity / 100
            displayUnit = "dl"
        }
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        let localizedUnit: String
        switch displayUnit {
        case "pcs": localizedUnit = L10n.string("unit.pcs")
        case "tub": localizedUnit = L10n.string("unit.tub")
        case "bag": localizedUnit = L10n.string("unit.bag")
        case "bottle": localizedUnit = L10n.string("unit.bottle")
        case "jar": localizedUnit = L10n.string("unit.jar")
        case "can": localizedUnit = L10n.string("unit.can")
        case "pot": localizedUnit = L10n.string("unit.pot")
        default: localizedUnit = displayUnit
        }
        return localizedUnit.isEmpty ? number : "\(number) \(localizedUnit)"
    }
}
