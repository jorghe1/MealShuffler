import Foundation

enum IngredientUnits {
    struct Normalized {
        let quantity: Double
        let unit: String
    }

    static func normalize(quantity: Double, unit: String) -> Normalized {
        switch unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "kg": Normalized(quantity: quantity * 1_000, unit: "g")
        case "l", "liter": Normalized(quantity: quantity * 1_000, unit: "ml")
        case "dl": Normalized(quantity: quantity * 100, unit: "ml")
        case "cl": Normalized(quantity: quantity * 10, unit: "ml")
        case "ss": Normalized(quantity: quantity * 15, unit: "ml")
        case "ts": Normalized(quantity: quantity * 5, unit: "ml")
        default: Normalized(quantity: quantity, unit: unit.lowercased())
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
        return displayUnit.isEmpty ? number : "\(number) \(displayUnit)"
    }
}
