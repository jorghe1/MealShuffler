import SwiftUI

/// One person: what to call them, whether they are a child, when they eat at home, and what
/// they like.
///
/// Who is at the table changed day by day and had to be re-entered every week under "Plan this
/// day", three levels down. Most of it is a standing arrangement -- children here every other
/// week, training on Tuesdays -- so it is said once, here, and every new week starts from it.
struct MemberView: View {
    @Environment(AppStore.self) private var store
    @State private var draft: HouseholdMember

    init(member: HouseholdMember) {
        _draft = State(initialValue: member)
    }

    private var pattern: Binding<HomePattern> {
        Binding(get: { draft.homePattern ?? HomePattern() }, set: { draft.homePattern = $0 })
    }

    var body: some View {
        List {
            Section {
                TextField("Name", text: $draft.displayName)
                    .textContentType(.givenName)
                    .accessibilityIdentifier("member.name")
                if draft.role != .owner {
                    Picker("Role", selection: $draft.role) {
                        Text("Adult").tag(HouseholdRole.adult)
                        Text("Child").tag(HouseholdRole.child)
                    }
                }
            } footer: {
                if draft.role == .child {
                    Text("The kids view is offered to the children.")
                }
            }

            Section {
                Picker("Lives here", selection: pattern.weeks) {
                    Text("Every week").tag(HomePattern.Weeks.every)
                    Text("Even weeks").tag(HomePattern.Weeks.even)
                    Text("Odd weeks").tag(HomePattern.Weeks.odd)
                }
                .accessibilityIdentifier("member.weeks")
                VStack(alignment: .leading, spacing: AppTheme.Space.s) {
                    Text("Away for dinner on")
                        .font(.subheadline).foregroundStyle(AppTheme.ink)
                    AwayDayPicker(selection: pattern.awayDays)
                }
                .padding(.vertical, AppTheme.Space.xs)
                ForEach(previewWeeks, id: \.self) { start in
                    Label(Self.weekLine(for: draft.homePattern, weekStart: start), systemImage: "calendar")
                        .font(.footnote).foregroundStyle(AppTheme.muted)
                }
            } header: {
                Text("Eats at home")
            } footer: {
                Text("Even and odd weeks follow the week numbers in the calendar. Days this person is away get one portion less and leave out their dislikes. A day you plan by hand keeps what you set.")
            }

            Section {
                NavigationLink {
                    MemberTasteView(member: draft)
                } label: {
                    LabeledContent {
                        Text(Self.tasteSummary(for: draft, store: store)).lineLimit(1)
                    } label: {
                        Label("Tastes", systemImage: "heart")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(draft.displayName.isEmpty ? L10n.string("Member") : draft.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft) { _, updated in store.updateMember(updated) }
    }

    /// This week and next, so the effect of a pattern can be checked against the calendar.
    private var previewWeeks: [Date] {
        [store.plan.startDate, WeekAnchor.startOfNextWeek(after: store.plan.startDate)]
    }

    // MARK: - Summaries

    /// "Uke 42: borte tir, tor".
    static func weekLine(for pattern: HomePattern?, weekStart: Date) -> String {
        let pattern = pattern ?? HomePattern()
        let days = Weekday.ordered()
        let away = days.filter { !pattern.isHome(on: $0, inWeekStarting: weekStart) }
        let number = HomePattern.isoWeekNumber(of: days.first.map { $0.date(inWeekStarting: weekStart) } ?? weekStart)
        let text: String
        if away.isEmpty {
            text = L10n.string("home every day")
        } else if away.count == days.count {
            text = L10n.string("away all week")
        } else {
            text = L10n.string("away %@", dayList(away))
        }
        return L10n.string("Week %ld: %@", number, text)
    }

    /// "man, tir" rather than "man., tir.": the locale's short names carry a full stop that
    /// reads as clutter in a list.
    private static func dayList(_ days: [Weekday]) -> String {
        days.map { $0.shortName.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.joined(separator: ", ")
    }

    /// The line under a member in Family: a child, a pattern, then their tastes.
    static func summary(of member: HouseholdMember, store: AppStore) -> String {
        var parts: [String] = []
        if member.role == .child { parts.append(L10n.string("Child")) }
        if let pattern = member.homePattern, !pattern.isAlwaysHome {
            switch pattern.weeks {
            case .every: break
            case .even: parts.append(L10n.string("Even weeks"))
            case .odd: parts.append(L10n.string("Odd weeks"))
            }
            if !pattern.awayDays.isEmpty {
                let days = Weekday.ordered().filter { pattern.awayDays.contains($0) }
                parts.append(L10n.string("away %@", dayList(days)))
            }
        }
        parts.append(tasteSummary(for: member, store: store))
        return parts.joined(separator: " · ")
    }

    /// "Liker ikke Laks i ovn, Taco" -- the first few dishes this person swiped left on.
    static func tasteSummary(for member: HouseholdMember, store: AppStore) -> String {
        let opinions = store.memberPreferences[member.id] ?? [:]
        let disliked = opinions.filter { $0.value == .disliked }.keys.compactMap { store.meal(id: $0)?.name }.sorted()
        let liked = opinions.filter { $0.value == .liked }.count
        if !disliked.isEmpty {
            let shown = disliked.prefix(2).joined(separator: ", ")
            return disliked.count > 2
                ? L10n.string("Dislikes %@ and %ld more", shown, disliked.count - 2)
                : L10n.string("Dislikes %@", shown)
        }
        return liked > 0 ? L10n.string("Likes %ld dishes", liked) : L10n.string("No tastes saved yet")
    }
}

/// Seven days in a row, each a toggle for "away for dinner".
private struct AwayDayPicker: View {
    @Binding var selection: Set<Weekday>
    private let columns = Array(repeating: GridItem(.flexible(), spacing: AppTheme.Space.xs), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppTheme.Space.xs) {
            ForEach(Weekday.ordered()) { day in
                let isAway = selection.contains(day)
                Button {
                    Haptics.check()
                    if isAway { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(Weekday.shortSymbol(for: day).prefix(2).uppercased())
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: AppTheme.tapTarget)
                        .background(isAway ? AppTheme.warning.opacity(0.16) : AppTheme.raised)
                        .foregroundStyle(isAway ? AppTheme.warning : AppTheme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                                .stroke(isAway ? AppTheme.warning.opacity(0.5) : AppTheme.muted.opacity(0.25))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.name)
                .accessibilityValue(isAway ? Text("Away") : Text("Home"))
                .accessibilityAddTraits(isAway ? [.isSelected] : [])
                .accessibilityIdentifier("member.away.\(day.rawValue)")
            }
        }
    }
}
