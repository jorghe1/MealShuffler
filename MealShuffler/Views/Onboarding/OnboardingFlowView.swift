import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var store: AppStore
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? AppTheme.accent : AppTheme.ink.opacity(0.12))
                        .frame(height: 5)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)

            Group {
                switch step {
                case 0:
                    WelcomeStepView { withAnimation { step = 1 } }
                case 1:
                    TasteSwipeView { withAnimation { step = 2 } }
                default:
                    StarterRulesStepView { store.completeOnboarding() }
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .appBackground()
    }
}

private struct WelcomeStepView: View {
    let next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 112, height: 112)
                Image(systemName: "shuffle")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Middagene bestemmer seg selv.")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text("Fortell oss hva dere liker og hvilke regler som gjelder. Så lager vi en gjennomtenkt uke på ett trykk.")
                    .font(.title3)
                    .foregroundStyle(AppTheme.muted)
                    .lineSpacing(5)
            }

            Spacer()

            Button(action: next) {
                Text("Kom i gang")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 18))
        }
        .padding(24)
    }
}

private struct TasteSwipeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var index = 0
    @State private var offset: CGSize = .zero

    let finished: () -> Void
    private var onboardingMeals: [Meal] { Array(store.meals.prefix(7)) }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Hva liker dere?")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text("Sveip til høyre eller venstre")
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.top, 22)

            Text("\(min(index + 1, onboardingMeals.count)) av \(onboardingMeals.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)

            Spacer(minLength: 6)

            if index < onboardingMeals.count {
                let meal = onboardingMeals[index]
                TasteCard(meal: meal, offset: offset)
                    .offset(offset)
                    .rotationEffect(.degrees(Double(offset.width / 18)))
                    .gesture(
                        DragGesture()
                            .onChanged { offset = $0.translation }
                            .onEnded { value in
                                if abs(value.translation.width) > 90 {
                                    choose(value.translation.width > 0 ? .liked : .disliked)
                                } else {
                                    withAnimation(.spring(response: 0.3)) { offset = .zero }
                                }
                            }
                    )
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 6)

            HStack(spacing: 22) {
                ChoiceButton(symbol: "xmark", label: "Nei takk", color: .red) { choose(.disliked) }
                ChoiceButton(symbol: "heart.fill", label: "Liker", color: AppTheme.accent) { choose(.liked) }
            }
            .padding(.bottom, 24)
        }
    }

    private func choose(_ preference: MealPreference) {
        guard index < onboardingMeals.count else { return }
        let direction: CGFloat = preference == .liked ? 1 : -1
        store.setPreference(preference, for: onboardingMeals[index])
        withAnimation(.easeIn(duration: 0.16)) { offset.width = direction * 520 }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            offset = .zero
            if index + 1 >= onboardingMeals.count {
                finished()
            } else {
                index += 1
            }
        }
    }
}

private struct TasteCard: View {
    let meal: Meal
    let offset: CGSize

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [AppTheme.accentSoft, Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(meal.emoji)
                    .font(.system(size: 112))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 8)

                if abs(offset.width) > 35 {
                    Text(offset.width > 0 ? "LIKER" : "NEI TAKK")
                        .font(.title2.bold())
                        .foregroundStyle(offset.width > 0 ? AppTheme.accent : .red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(offset.width > 0 ? AppTheme.accent : .red, lineWidth: 3)
                        )
                        .rotationEffect(.degrees(offset.width > 0 ? -8 : 8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: offset.width > 0 ? .topLeading : .topTrailing)
                        .padding(22)
                }
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text(meal.name)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text(meal.subtitle)
                    .font(.body)
                    .foregroundStyle(AppTheme.muted)
                Label("Ca. \(meal.prepMinutes) min", systemImage: "clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(.white)
        }
        .frame(height: 430)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
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
                    .background(.white)
                    .clipShape(Circle())
                    .shadow(color: AppTheme.ink.opacity(0.1), radius: 10, y: 5)
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(color)
        }
    }
}

private struct StarterRulesStepView: View {
    @EnvironmentObject private var store: AppStore
    let finished: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Noen regler å starte med")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text("Skru av det som ikke passer. Du kan lage langt mer detaljerte regler senere.")
                    .foregroundStyle(AppTheme.muted)
                    .lineSpacing(4)
            }
            .padding(.top, 28)

            VStack(spacing: 12) {
                HStack {
                    Label("Personer til middag", systemImage: "person.2")
                        .font(.headline)
                    Spacer()
                    Stepper("\(store.householdSize)", value: $store.householdSize, in: 1...12)
                        .fixedSize()
                }
                .padding(16)
                .mealCard()

                ForEach(store.rules) { rule in
                    HStack(spacing: 14) {
                        Image(systemName: icon(for: rule))
                            .font(.title3)
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(AppTheme.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.title).font(.headline)
                            Text(rule.summary(meals: store.meals))
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { store.rules.first(where: { $0.id == rule.id })?.isEnabled ?? false },
                            set: { _ in store.toggleRule(rule) }
                        ))
                        .labelsHidden()
                    }
                    .padding(16)
                    .mealCard()
                }
            }

            Spacer()

            Button(action: finished) {
                HStack {
                    Text("Lag min første uke")
                    Image(systemName: "shuffle")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 18))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func icon(for rule: PlanningRule) -> String {
        switch rule.constraint {
        case .requiredOn: "calendar.badge.checkmark"
        case .excludedOn: "calendar.badge.minus"
        case .maximumPerWeek: "arrow.down.circle"
        case .minimumPerWeek: "arrow.up.circle"
        case .maximumPrepTime: "clock"
        }
    }
}
