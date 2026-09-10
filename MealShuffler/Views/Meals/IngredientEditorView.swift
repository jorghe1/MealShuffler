import SwiftUI

struct IngredientEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let original: Ingredient
    let save: (Ingredient) -> Void
    @State private var name: String
    @State private var quantity: String
    @State private var upper: String
    @State private var unit: String
    @State private var packageQuantity: String
    @State private var packageUnit: String
    @State private var section: String
    @State private var note: String
    @State private var aisle: GroceryAisle
    init(ingredient: Ingredient, save: @escaping (Ingredient) -> Void) {
        original = ingredient; self.save = save
        _name = State(initialValue: ingredient.name)
        _quantity = State(initialValue: ingredient.hasKnownQuantity ? String(ingredient.quantity) : "")
        _upper = State(initialValue: ingredient.upperQuantity.map { String($0) } ?? "")
        _unit = State(initialValue: ingredient.unit)
        _packageQuantity = State(initialValue: ingredient.packageQuantity.map { String($0) } ?? "")
        _packageUnit = State(initialValue: ingredient.packageUnit ?? "")
        _section = State(initialValue: ingredient.section ?? "")
        _note = State(initialValue: ingredient.amountNote ?? "")
        _aisle = State(initialValue: ingredient.aisle)
    }
    private func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
    private var valid: Bool {
        let fields = [quantity, upper, packageQuantity]
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && fields.allSatisfy { $0.isEmpty || number($0).map { $0.isFinite && $0 > 0 && $0 <= 1_000_000 } == true }
            && (upper.isEmpty || (!quantity.isEmpty && number(upper)! >= number(quantity)!))
            && (packageQuantity.isEmpty == packageUnit.isEmpty)
    }
    var body: some View {
        NavigationStack {
            Form {
                if let text = original.originalText { Section("Original source") { Text(text).textSelection(.enabled) } }
                Section("Ingredient") {
                    TextField("Name", text: $name)
                    TextField("Amount", text: $quantity).keyboardType(.decimalPad)
                    TextField("Upper amount (optional)", text: $upper).keyboardType(.decimalPad)
                    TextField("Unit", text: $unit)
                    TextField("Amount note (optional)", text: $note)
                    Text("Leave the amount empty when it is not specified. Use an amount note for “to taste”.").font(.caption)
                }
                Section("Package size") {
                    TextField("Amount per package", text: $packageQuantity).keyboardType(.decimalPad)
                    TextField("Package unit", text: $packageUnit)
                }
                Section {
                    TextField("Recipe section", text: $section)
                    Picker("Aisle", selection: $aisle) { ForEach(GroceryAisle.allCases) { Text($0.name).tag($0) } }
                }
            }.navigationTitle("Edit ingredient")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var item = Ingredient(name: name.trimmingCharacters(in: .whitespacesAndNewlines), quantity: number(quantity) ?? 0, unit: unit, aisle: aisle)
                        item.lineID = original.id; item.upperQuantity = number(upper)
                        item.packageQuantity = number(packageQuantity); item.packageUnit = packageUnit.isEmpty ? nil : packageUnit
                        item.section = section.isEmpty ? nil : section; item.amountNote = note.isEmpty ? nil : note
                        save(item); dismiss()
                    }.disabled(!valid)
                }
            }
        }
    }
}

struct SourcePhotoView: View {
    let data: Data
    @State private var zoom = 1.0
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                if let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: max(300, UIScreen.main.bounds.width - 32) * zoom)
                        .accessibilityLabel("Original recipe photo")
                }
            }.toolbar {
                ToolbarItem(placement: .bottomBar) { Slider(value: $zoom, in: 1...4) { Text("Zoom") } }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
