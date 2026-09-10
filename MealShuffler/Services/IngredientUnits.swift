import Foundation

enum IngredientUnits {
    static func key(name: String, unit: String) -> String {
        let name = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name + "|" + normalize(quantity: 1, unit: unit).unit
    }
    struct Normalized {
        let quantity: Double
        let unit: String
    }

    static func normalize(quantity: Double, unit: String) -> Normalized {
        switch unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "kg": Normalized(quantity: quantity * 1_000, unit: "g")
        case "oz", "ounce", "ounces": Normalized(quantity: quantity * 28.349523125, unit: "g")
        case "lb", "lbs", "pound", "pounds": Normalized(quantity: quantity * 453.59237, unit: "g")
        case "cups": Normalized(quantity: quantity, unit: "cup")
        case "cloves", "fedd": Normalized(quantity: quantity, unit: "clove")
        case "l", "liter", "litre": Normalized(quantity: quantity * 1_000, unit: "ml")
        case "dl": Normalized(quantity: quantity * 100, unit: "ml")
        case "cl": Normalized(quantity: quantity * 10, unit: "ml")
        case "ss", "tbsp", "tablespoon", "tablespoons": Normalized(quantity: quantity * 15, unit: "ml")
        case "ts", "tsp", "teaspoon", "teaspoons": Normalized(quantity: quantity * 5, unit: "ml")
        case "stk", "piece", "pieces", "pc", "pcs": Normalized(quantity: quantity, unit: "pcs")
        case "beger", "tub", "tubs": Normalized(quantity: quantity, unit: "tub")
        case "pose", "poser", "bag", "bags": Normalized(quantity: quantity, unit: "bag")
        case "flaske", "flasker", "bottle", "bottles": Normalized(quantity: quantity, unit: "bottle")
        case "glass", "jar", "jars": Normalized(quantity: quantity, unit: "jar")
        case "boks", "bokser", "can", "cans", "tin", "tins": Normalized(quantity: quantity, unit: "can")
        case "pakke", "pakker", "pack", "packs": Normalized(quantity: quantity, unit: "pack")
        case "potte", "potter", "pot", "pots": Normalized(quantity: quantity, unit: "pot")
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
        case "clove", "cloves", "fedd": localizedUnit = L10n.string(quantity == 1 ? "unit.clove" : "unit.clove.plural")
        case "cup", "cups": localizedUnit = L10n.string(quantity == 1 ? "unit.cup" : "unit.cup.plural")
        case "pack": localizedUnit = L10n.string(quantity == 1 ? "unit.pack" : "unit.pack.plural")
        case "pcs": localizedUnit = L10n.string("unit.pcs")
        case "tub": localizedUnit = L10n.string(quantity == 1 ? "unit.tub" : "unit.tub.plural")
        case "bag": localizedUnit = L10n.string(quantity == 1 ? "unit.bag" : "unit.bag.plural")
        case "bottle": localizedUnit = L10n.string(quantity == 1 ? "unit.bottle" : "unit.bottle.plural")
        case "jar": localizedUnit = L10n.string(quantity == 1 ? "unit.jar" : "unit.jar.plural")
        case "can": localizedUnit = L10n.string(quantity == 1 ? "unit.can" : "unit.can.plural")
        case "pot": localizedUnit = L10n.string(quantity == 1 ? "unit.pot" : "unit.pot.plural")
        default: localizedUnit = displayUnit
        }
        return localizedUnit.isEmpty ? number : "\(number) \(localizedUnit)"
    }
}
