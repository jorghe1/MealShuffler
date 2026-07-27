import SwiftUI

struct WeekPlanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedMeal: Meal?
    @State private var editingDay: Weekday?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                plannerHeader
                if !store.conflicts.isEmpty { conflictBanner }

                ForEach(Weekday.allCases) { day in
                    if let item = store.plan[day] {
                        DayPlanCard(
                            day: day,
                            item: item,
                            meal: item.mealID.flatMap { store.meal(id: $0) },
                            explanation: store.explanation(for: day),
                            isFavorite: item.mealID.map { store.favoriteMealIDs.contains($0) } ?? false,
                            open: { if let id = item.mealID { selectedMeal = store.meal(id: id) } },
                            editContext: { editingDay = day },
                            toggleLock: { store.toggleLock(day: day) },
                            shuffle: { intent in withAnimation(.snappy) { store.shuffle(day: day, intent: intent) } },
                            snooze: {
                                if let id = item.mealID, let meal = store.meal(id: id) { store.snooze(meal, on: day) }
                            },
                            toggleFavorite: {
                                if let id = item.mealID, let meal = store.meal(id: id) { store.toggleFavorite(meal) }
                            },
                            markCooked: {
                                if let id = item.mealID, let meal = store.meal(id: id) { store.markCooked(meal, on: day) }
                            },
                            markSkipped: {
                                if let id = item.mealID, let meal = store.meal(id: id) { store.markSkipped(meal, on: day) }
                            },
                            swapWith: { otherDay in store.swapMeals(between: day, and: otherDay) }
                        )
                    }
                }

                Button { withAnimation(.snappy) { store.shuffleAll() } } label: {
                    Label("Shuffle resten", systemImage: "shuffle")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 18))
                .padding(.top, 4).padding(.bottom, 28)
            }
            .padding(.horizontal, 16)
        }
        .appBackground()
        .navigationTitle("Denne uken")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink { MealHistoryView() } label: { Image(systemName: "clock.arrow.circlepath") }
                ShareLink(item: PlanTextExporter.weeklyPlan(store.plan, meals: store.meals)) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .sheet(item: $selectedMeal) { meal in
            MealDetailView(meal: meal).presentationDetents([.medium, .large])
        }
        .sheet(item: $editingDay) { day in
            DayContextEditor(day: day, initialContext: store.context(for: day)) { store.updateContext($0, for: day) }
                .presentationDetents([.medium, .large])
        }
    }

    private var plannerHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MIDDAGSPLAN").font(.caption.bold()).foregroundStyle(AppTheme.accent)
                    Text("God uke, god appetitt")
                        .font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.ink)
                }
                Spacer()
                Button { withAnimation(.snappy) { store.shuffleAll() } } label: {
                    Image(systemName: "shuffle").font(.title2.bold()).frame(width: 54, height: 54)
                        .background(AppTheme.accent).foregroundStyle(.white).clipShape(Circle())
                        .shadow(color: AppTheme.accent.opacity(0.25), radius: 10, y: 5)
                }.accessibilityLabel("Shuffle uke")
            }
            Text("Trykk på ••• for raskere, billigere, favoritter eller bytte av dag.")
                .font(.subheadline).foregroundStyle(AppTheme.muted)
        }.padding(.vertical, 14)
    }

    private var conflictBanner: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.conflicts) { conflict in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(conflict.message).font(.caption)
                        if let suggestion = conflict.suggestion { Text(suggestion).font(.caption2).foregroundStyle(AppTheme.muted) }
                        if let ruleID = conflict.ruleID {
                            Button("Gjør regelen myk") { store.setRuleStrength(.preferred, ruleID: ruleID) }
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }.padding(.top, 8)
        } label: {
            Label("\(store.conflicts.count) regelkonflikt\(store.conflicts.count == 1 ? "" : "er")", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.warning)
        }
        .padding(14).background(AppTheme.warning.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct DayPlanCard: View {
    let day: Weekday
    let item: PlannedMeal
    let meal: Meal?
    let explanation: String?
    let isFavorite: Bool
    let open: () -> Void
    let editContext: () -> Void
    let toggleLock: () -> Void
    let shuffle: (MealSwapIntent) -> Void
    let snooze: () -> Void
    let toggleFavorite: () -> Void
    let markCooked: () -> Void
    let markSkipped: () -> Void
    let swapWith: (Weekday) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Text(cardEmoji).font(.system(size: 36)).frame(width: 60, height: 60)
                    .background(AppTheme.accentSoft.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 17))
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.name.uppercased()).font(.caption2.bold()).tracking(0.8).foregroundStyle(AppTheme.accent)
                    Text(cardTitle).font(.headline).foregroundStyle(AppTheme.ink).lineLimit(1)
                    Text(cardMetadata).font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 4)
                Button(action: toggleLock) {
                    Image(systemName: item.isLocked ? "lock.fill" : "lock.open")
                        .frame(width: 34, height: 34).foregroundStyle(item.isLocked ? AppTheme.accent : AppTheme.muted)
                }.buttonStyle(.plain)
                menu
            }
            .padding(12).contentShape(Rectangle()).onTapGesture(perform: open)

            if let explanation {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "sparkles").foregroundStyle(AppTheme.accent)
                    Text(explanation).font(.caption).foregroundStyle(AppTheme.muted)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.bottom, 11)
            }
        }.mealCard()
    }

    private var menu: some View {
        Menu {
            Section("Bytt middag") {
                ForEach(MealSwapIntent.allCases) { intent in
                    Button { shuffle(intent) } label: { Label(intent.name, systemImage: intent.symbol) }
                }
            }
            Section("Flytt") {
                Menu("Bytt med en annen dag") {
                    ForEach(Weekday.allCases.filter { $0 != day }) { other in Button(other.name) { swapWith(other) } }
                }
            }
            if meal != nil {
                Section {
                    Button(action: markCooked) { Label("Vi laget denne", systemImage: "checkmark.seal") }
                    Button(action: markSkipped) { Label("Ikke aktuell i dag", systemImage: "forward") }
                    Button(action: toggleFavorite) { Label(isFavorite ? "Fjern familiefavoritt" : "Familiefavoritt", systemImage: isFavorite ? "heart.slash" : "heart") }
                    Button(role: .destructive, action: snooze) { Label("Ikke igjen på en stund", systemImage: "calendar.badge.minus") }
                }
            }
            Button(action: editContext) { Label("Planlegg denne dagen", systemImage: "person.2") }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3).frame(width: 36, height: 36).foregroundStyle(AppTheme.muted)
        }
    }

    private var cardEmoji: String {
        if let meal { return meal.emoji }
        switch item.kind { case .away: "🏃"; case .takeaway: "🥡"; case .leftovers: "♻️"; case .meal: "🍽️" }
    }
    private var cardTitle: String {
        if case .leftovers = item.kind { return meal.map { "Rester: \($0.name)" } ?? "Rester" }
        if let meal { return meal.name }
        switch item.kind { case .away: "Ingen middag hjemme"; case .takeaway: "Takeaway"; default: "Ikke planlagt" }
    }
    private var cardMetadata: String {
        if let meal { return "\(meal.prepMinutes) min · \(item.servings) porsjoner" }
        return item.kind == .away ? "Fridag" : "\(item.servings) personer"
    }
}

private struct DayContextEditor: View {
    @Environment(\.dismiss) private var dismiss
    let day: Weekday
    let save: (DayPlanContext) -> Void
    @State private var context: DayPlanContext
    @State private var hasTimeLimit: Bool

    init(day: Weekday, initialContext: DayPlanContext, save: @escaping (DayPlanContext) -> Void) {
        self.day = day; self.save = save
        _context = State(initialValue: initialContext)
        _hasTimeLimit = State(initialValue: initialContext.maximumPrepMinutes != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Hva skjer \(day.name.lowercased())?") {
                    Picker("Plan", selection: $context.mode) {
                        ForEach(DayDinnerMode.allCases) { Label($0.name, systemImage: symbol($0)).tag($0) }
                    }
                    Stepper("\(context.diners) som spiser", value: $context.diners, in: 1...20)
                }
                if context.mode == .cook {
                    Section("Matlaging") {
                        Stepper(context.extraServings == 0 ? "Ingen ekstra porsjoner" : "Lag \(context.extraServings) ekstra", value: $context.extraServings, in: 0...12)
                        Toggle("Tidsgrense", isOn: $hasTimeLimit)
                        if hasTimeLimit {
                            Stepper("Maks \(context.maximumPrepMinutes ?? 30) minutter", value: Binding(
                                get: { context.maximumPrepMinutes ?? 30 }, set: { context.maximumPrepMinutes = $0 }
                            ), in: 10...120, step: 5)
                        }
                    }
                }
                if context.mode == .leftovers {
                    Section("Rester fra") {
                        Picker("Tidligere dag", selection: $context.leftoverSourceDay) {
                            Text("Finn automatisk").tag(nil as Weekday?)
                            ForEach(daysBefore) { Text($0.name).tag($0 as Weekday?) }
                        }
                    }
                }
            }
            .navigationTitle(day.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        if !hasTimeLimit { context.maximumPrepMinutes = nil }
                        save(context); dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
    }

    private var daysBefore: [Weekday] {
        guard let index = Weekday.allCases.firstIndex(of: day) else { return [] }
        return Array(Weekday.allCases.prefix(index))
    }
    private func symbol(_ mode: DayDinnerMode) -> String {
        switch mode { case .cook: "fork.knife"; case .leftovers: "arrow.3.trianglepath"; case .away: "figure.run"; case .takeaway: "takeoutbag.and.cup.and.straw" }
    }
}

private struct MealDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let meal: Meal
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ZStack { RoundedRectangle(cornerRadius: 28).fill(AppTheme.accentSoft); Text(meal.emoji).font(.system(size: 105)) }.frame(height: 220)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(meal.name).font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(meal.subtitle).foregroundStyle(AppTheme.muted)
                        Label("\(meal.prepMinutes) minutter · \(meal.defaultServings) porsjoner", systemImage: "clock")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ingredienser").font(.title3.bold())
                        ForEach(meal.ingredients) { ingredient in
                            HStack { Text(ingredient.name); Spacer(); Text(IngredientUnits.display(quantity: ingredient.quantity, unit: ingredient.unit)).foregroundStyle(AppTheme.muted) }
                            Divider()
                        }
                    }
                    if !meal.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Fremgangsmåte").font(.title3.bold())
                            ForEach(Array(meal.instructions.enumerated()), id: \.offset) { index, instruction in
                                HStack(alignment: .top) { Text("\(index + 1)").font(.caption.bold()).frame(width: 26, height: 26).background(AppTheme.accentSoft).clipShape(Circle()); Text(instruction) }
                            }
                        }
                    }
                }.padding(20)
            }.appBackground()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Ferdig") { dismiss() } } }
        }
    }
}
