import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var store: AppStore
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stepCount = 3

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<Self.stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? AppTheme.accent : AppTheme.ink.opacity(0.12))
                        .frame(height: 5)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .accessibilityElement()
            .accessibilityLabel(L10n.string("Step %ld of %ld", step + 1, Self.stepCount))

            Group {
                switch step {
                case 0:
                    WelcomeStepView { withAnimation(reduceMotion ? nil : .default) { step = 1 } }
                case 1:
                    TasteSwipeView {
                        // Generate before showing, so the last step is a real week rather
                        // than a form standing between the user and the payoff.
                        store.shuffleAll()
                        withAnimation(reduceMotion ? nil : .default) { step = 2 }
                    }
                default:
                    FirstWeekStepView { store.completeOnboarding() }
                }
            }
            .id(step)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .appBackground()
    }
}

private struct WelcomeStepView: View {
    let next: () -> Void

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 112, height: 112)
                Image(systemName: "shuffle")
                    .font(.system(.largeTitle, design: .default, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Dinner plans itself.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text("Tell us what you like and which rules matter. Then we'll create a thoughtful week in one tap.")
                    .font(.title3)
                    .foregroundStyle(AppTheme.muted)
                    .lineSpacing(5)
            }

            Spacer()

            Button(action: next) {
                Text("Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.controlRadius))
        }
        .padding(24)
        }
    }
}

private struct TasteSwipeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var index = 0
    @State private var offset: CGSize = .zero
    /// Fixed once, so the deck does not reshuffle underneath the person swiping it.
    @State private var deck: [Meal] = []
    @State private var isAdvancing = false
    @State private var transitionTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let finished: () -> Void

    private static let deckSize = 8

    var body: some View {
        ScrollView {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("What do you like?")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text(L10n.string("Preferences for %@", store.household.members.first(where: { $0.role == .owner })?.displayName ?? L10n.string("Me")))
                Text("Swipe right or left")
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.top, 22)

            Text(L10n.string("%ld of %ld", min(index + 1, deck.count), deck.count))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)

            Spacer(minLength: 6)

            if index < deck.count {
                let meal = deck[index]
                TasteCard(meal: meal, offset: offset)
                    .offset(offset)
                    .rotationEffect(.degrees(reduceMotion ? 0 : Double(offset.width / 18)))
                    .gesture(
                        DragGesture()
                            .onChanged { offset = $0.translation }
                            .onEnded { value in
                                if abs(value.translation.width) > 90 {
                                    choose(value.translation.width > 0 ? .liked : .disliked)
                                } else {
                                    withAnimation(reduceMotion ? nil : .spring(response: 0.3)) { offset = .zero }
                                }
                            }
                    )
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 6)

            HStack(spacing: 22) {
                ChoiceButton(symbol: "xmark", label: L10n.string("No thanks"), color: AppTheme.destructive) {
                    choose(.disliked)
                }
                ChoiceButton(symbol: "heart.fill", label: L10n.string("Like"), color: AppTheme.accent) {
                    choose(.liked)
                }
            }

            .disabled(isAdvancing)
            HStack {
                Button("Neutral") { choose(.neutral) }.disabled(isAdvancing)
                Spacer()
                Button("Skip remaining") { guard !isAdvancing else { return }; isAdvancing = true; finished() }
            }.padding(.horizontal, 24)

            // One mis-swipe used to be permanent, on a screen whose entire purpose is
            // recording opinions correctly.
            Button {
                goBack()
            } label: {
                Label("Back", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(index == 0 || isAdvancing)
            .opacity(index == 0 ? 0 : 1)
            .padding(.bottom, 20)
        }
        }
        .onAppear {
            if deck.isEmpty { deck = Self.buildDeck(from: store.meals) }
        }
        .onDisappear { transitionTask?.cancel() }
    }

    /// A spread across the library rather than the first seven rows of it.
    ///
    /// `prefix(7)` asked every household on earth the same seven questions, in the same
    /// order, and never showed anything from the back half of the library.
    static func buildDeck(from meals: [Meal]) -> [Meal] {
        var byCategory: [WeekCompositionView.Category: [Meal]] = [:]
        for meal in meals { byCategory[WeekCompositionView.Category.of(meal), default: []].append(meal) }

        var chosen: [Meal] = []
        for category in WeekCompositionView.Category.allCases {
            if let pick = byCategory[category]?.randomElement() { chosen.append(pick) }
        }
        let chosenIDs = Set(chosen.map(\.id))
        let filler = meals.filter { !chosenIDs.contains($0.id) }.shuffled()
        chosen.append(contentsOf: filler.prefix(max(0, deckSize - chosen.count)))
        return chosen.shuffled()
    }

    private func choose(_ preference: MealPreference) {
        guard !isAdvancing, index < deck.count else { return }
        isAdvancing = true
        let direction: CGFloat = preference == .liked ? 1 : -1
        store.setPreference(preference, for: deck[index])
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.16)) { offset.width = direction * 520 }

        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
            guard !Task.isCancelled else { return }
            offset = .zero
            if index + 1 >= deck.count {
                finished()
            } else {
                index += 1
                isAdvancing = false
            }
        }
    }

    private func goBack() {
        guard !isAdvancing, index > 0 else { return }
        index -= 1
        offset = .zero
        // Clears the opinion rather than leaving the old one standing behind the card.
        store.setPreference(.neutral, for: deck[index])
    }
}

private struct TasteCard: View {
    let meal: Meal
    let offset: CGSize

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [AppTheme.accentSoft, AppTheme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(meal.emoji)
                    .font(.system(size: 112))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 8)
                    .accessibilityHidden(true)

                if abs(offset.width) > 35 {
                    Text(offset.width > 0 ? L10n.string("LIKE") : L10n.string("NO THANKS"))
                        .font(.title2.bold())
                        .foregroundStyle(offset.width > 0 ? AppTheme.accent : AppTheme.destructive)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.chipRadius)
                                .stroke(offset.width > 0 ? AppTheme.accent : AppTheme.destructive, lineWidth: 3)
                        )
                        .rotationEffect(.degrees(offset.width > 0 ? -8 : 8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: offset.width > 0 ? .topLeading : .topTrailing)
                        .padding(22)
                }
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text(meal.name)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text(meal.subtitle)
                    .font(.body)
                    .foregroundStyle(AppTheme.muted)
                Label(L10n.string("About %ld min", meal.prepMinutes), systemImage: "clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(AppTheme.surface)
            .accessibilityElement(children: .combine)
        }
        // Was a fixed 430pt, which clipped its own text at larger accessibility sizes.
        .frame(minHeight: 380)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
        .shadow(color: AppTheme.ink.opacity(0.13), radius: 22, y: 12)
    }
}

private struct ChoiceButton: View {
    let symbol: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.title2.bold())
                    .frame(width: 62, height: 62)
                    .background(AppTheme.raised)
                    .clipShape(Circle())
                    .shadow(color: AppTheme.ink.opacity(0.1), radius: 10, y: 5)
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(color)
        }
    }
}
