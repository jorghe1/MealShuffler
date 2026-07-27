import SwiftUI

struct CommunityView: View {
    @EnvironmentObject private var community: CommunityStore
    @EnvironmentObject private var store: AppStore
    @State private var showingPublish = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("From other dinner tables")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                        Text("A local test community – ready for an external backend later.")
                            .font(.subheadline).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                }.padding(.top, 12)

                ForEach(community.recipes) { recipe in
                    NavigationLink { CommunityRecipeDetail(recipeID: recipe.id) } label: {
                        CommunityRecipeCard(recipe: recipe)
                    }.buttonStyle(.plain)
                }
                if community.isLoading { ProgressView().padding(30) }
                Color.clear.frame(height: 20)
            }.padding(.horizontal, 16)
        }
        .appBackground()
        .navigationTitle("Community")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingPublish = true } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .task { if community.recipes.isEmpty { await community.load() } }
        .sheet(isPresented: $showingPublish) { PublishRecipeView().environmentObject(store).environmentObject(community) }
        .alert("Community", isPresented: Binding(get: { community.errorMessage != nil }, set: { if !$0 { community.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(community.errorMessage ?? L10n.string("Unknown error")) }
    }
}

private struct CommunityRecipeCard: View {
    let recipe: CommunityRecipe
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                LinearGradient(colors: [AppTheme.accentSoft, .white], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(recipe.meal.emoji).font(.system(size: 72))
            }.frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.meal.name).font(.title3.bold()).foregroundStyle(AppTheme.ink)
                Text(L10n.string("by %@", recipe.author.displayName)).font(.caption).foregroundStyle(AppTheme.muted)
                HStack {
                    Label(recipe.ratingCount == 0 ? L10n.string("New") : recipe.averageRating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                    Label(L10n.string("Cooked %ld times", recipe.cookedCount), systemImage: "fork.knife")
                }.font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
            }.padding(.horizontal, 4)
        }.padding(12).mealCard()
    }
}

private struct CommunityRecipeDetail: View {
    @EnvironmentObject private var community: CommunityStore
    @EnvironmentObject private var store: AppStore
    let recipeID: UUID
    @State private var stars = 5
    @State private var wouldCookAgain = true
    @State private var added = false
    @State private var showingReport = false
    @State private var reportReason: CommunityReportReason = .inaccurate
    @State private var reportSent = false

    private var recipe: CommunityRecipe? { community.recipes.first(where: { $0.id == recipeID }) }

    var body: some View {
        ScrollView {
            if let recipe {
                VStack(alignment: .leading, spacing: 20) {
                    ZStack { RoundedRectangle(cornerRadius: 28).fill(AppTheme.accentSoft); Text(recipe.meal.emoji).font(.system(size: 105)) }.frame(height: 230)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recipe.meal.name).font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(L10n.string("Shared by %@", recipe.author.displayName)).foregroundStyle(AppTheme.muted)
                        Label(
                            L10n.string(
                                "%@ from %ld ratings",
                                recipe.averageRating.formatted(.number.precision(.fractionLength(1))),
                                recipe.ratingCount
                            ),
                            systemImage: "star.fill"
                        ).foregroundStyle(AppTheme.accent)
                        if let attribution = recipe.attribution, let url = URL(string: attribution) {
                            Link("View original source", destination: url).font(.caption)
                        }
                    }

                    Button { add(recipe) } label: {
                        Label(
                            added ? L10n.string("Added to my meals") : L10n.string("Add to my meals"),
                            systemImage: added ? "checkmark" : "plus"
                        )
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    }.buttonStyle(.borderedProminent).disabled(added)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Rate this meal").font(.title3.bold())
                        HStack {
                            ForEach(1...5, id: \.self) { value in
                                Button { stars = value } label: { Image(systemName: value <= stars ? "star.fill" : "star").font(.title2).foregroundStyle(.yellow) }
                            }
                        }
                        Toggle("Would cook again", isOn: $wouldCookAgain)
                        Button("Submit rating") {
                            Task { await community.rate(recipeID: recipe.id, householdID: store.household.id, stars: stars, wouldCookAgain: wouldCookAgain) }
                        }.buttonStyle(.bordered)
                    }.padding(18).mealCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ingredients").font(.title3.bold())
                        ForEach(recipe.meal.ingredients) { item in
                            HStack { Text(item.name); Spacer(); Text(IngredientUnits.display(quantity: item.quantity, unit: item.unit)).foregroundStyle(AppTheme.muted) }
                        }
                    }
                    Button("Report recipe", role: .destructive) { showingReport = true }
                        .font(.caption)
                }.padding(16)
            }
        }
        .appBackground().navigationTitle("Recipe").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Why are you reporting this?", isPresented: $showingReport) {
            ForEach(CommunityReportReason.allCases) { reason in
                Button(reason.name) {
                    reportReason = reason
                    Task { reportSent = await community.report(recipeID: recipeID, householdID: store.household.id, reason: reason) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Thanks for letting us know", isPresented: $reportSent) {
            Button("OK", role: .cancel) {}
        } message: { Text("The report has been saved for moderation.") }
    }

    private func add(_ recipe: CommunityRecipe) {
        let source = recipe.meal
        store.saveMeal(Meal(
            name: source.name, subtitle: source.subtitle, emoji: source.emoji,
            prepMinutes: source.prepMinutes, tags: source.tags, ingredients: source.ingredients,
            defaultServings: source.defaultServings, estimatedCostNOK: source.estimatedCostNOK,
            instructions: source.instructions, source: .community(recipe.id)
        ))
        added = true
    }
}

private struct PublishRecipeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var community: CommunityStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMealID: UUID?
    @State private var confirmsRights = false
    @State private var isPublishing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Choose one of your meals") {
                    if store.customMeals.isEmpty {
                        Text("Create or import your own meal first.").foregroundStyle(.secondary)
                    } else {
                        Picker("Meal", selection: $selectedMealID) {
                            Text("Choose…").tag(nil as UUID?)
                            ForEach(store.customMeals) { Text("\($0.emoji) \($0.name)").tag($0.id as UUID?) }
                        }
                    }
                }
                Section("Before publishing") {
                    Toggle("I have the right to share the text and any images", isOn: $confirmsRights)
                    Text("Sources and attribution must be preserved. Moderation and reporting will be enabled before the community opens publicly.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button {
                        Task { await publish() }
                    } label: {
                        HStack { Text("Publish for test families"); Spacer(); if isPublishing { ProgressView() } }
                    }.disabled(selectedMealID == nil || !confirmsRights || isPublishing)
                }
            }
            .navigationTitle("Share recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func publish() async {
        guard let id = selectedMealID, let meal = store.meal(id: id) else { return }
        isPublishing = true
        if await community.publish(meal: meal, household: store.household) { dismiss() }
        isPublishing = false
    }
}
