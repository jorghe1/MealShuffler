import SwiftUI

/// Step-by-step cooking, with the screen kept awake.
///
/// The app was only useful while planning. This is the other half of the promise: it is open
/// on the counter while dinner is actually being made, which is also when marking a meal
/// cooked costs nothing rather than being an admin task remembered later.
struct CookModeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let meal: Meal
    let day: Weekday
    let servings: Int

    @State private var step = 0
    @State private var gathered: Set<String> = []
    @State private var didMarkCooked = false

    private var scale: Double { Double(servings) / Double(max(meal.defaultServings, 1)) }
    private var hasSteps: Bool { !meal.instructions.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if hasSteps { progressBar }

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ingredients
                        if hasSteps { instructions } else { noSteps }
                        Color.clear.frame(height: 20)
                    }
                    .padding(20)
                }

                footer
            }
            .appBackground()
            .navigationTitle(meal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        // Nobody wants to wipe their hands to wake the screen mid-recipe.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(meal.instructions.indices, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? AppTheme.accent : AppTheme.ink.opacity(0.12))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .accessibilityElement()
        .accessibilityLabel(L10n.string("Step %ld of %ld", step + 1, meal.instructions.count))
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ingredients").font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Text(L10n.string("%ld servings", servings))
                    .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
            }
            ForEach(meal.ingredients) { ingredient in
                Button {
                    if gathered.contains(ingredient.id) { gathered.remove(ingredient.id) }
                    else { gathered.insert(ingredient.id) }
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: gathered.contains(ingredient.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(gathered.contains(ingredient.id) ? AppTheme.accent : AppTheme.muted.opacity(0.45))
                        Text(ingredient.name)
                            .foregroundStyle(AppTheme.ink)
                            .strikethrough(gathered.contains(ingredient.id))
                        Spacer()
                        // Scaled to the servings actually being cooked, not the recipe's default.
                        Text(IngredientUnits.display(quantity: ingredient.quantity * scale, unit: ingredient.unit))
                            .font(.subheadline).foregroundStyle(AppTheme.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(gathered.contains(ingredient.id) ? [.isButton, .isSelected] : [.isButton])
            }
        }
        .padding(18)
        .mealCard()
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("Step %ld of %ld", step + 1, meal.instructions.count))
                .font(.caption.bold()).foregroundStyle(AppTheme.accent)
            Text(meal.instructions[min(step, meal.instructions.count - 1)])
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .mealCard()
    }

    private var noSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No steps saved for this meal")
                .font(.headline).foregroundStyle(AppTheme.ink)
            Text("Add them when you next edit the recipe and they will show up here.")
                .font(.subheadline).foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .mealCard()
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if hasSteps, step > 0 {
                Button { withAnimation(.snappy) { step -= 1 } } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline).padding(.vertical, 15).padding(.horizontal, 18)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 16))
            }

            if hasSteps, step < meal.instructions.count - 1 {
                Button { withAnimation(.snappy) { step += 1 } } label: {
                    Label("Next step", systemImage: "chevron.right")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
            } else {
                Button {
                    Haptics.success()
                    store.markCooked(meal, on: day)
                    didMarkCooked = true
                    dismiss()
                } label: {
                    Label("We cooked this", systemImage: "checkmark.seal")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .disabled(didMarkCooked)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .padding(.top, 8)
        .background(AppTheme.background)
    }
}
