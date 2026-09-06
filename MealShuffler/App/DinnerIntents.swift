import AppIntents
import Foundation

/// "Hey Siri, what's for dinner?"
///
/// Reads the saved plan through the same reader the widget uses, so it answers without
/// launching the app or touching the store.
struct WhatIsForDinnerIntent: AppIntent {
    static var title: LocalizedStringResource = "What's for dinner"
    static var description = IntentDescription("Reads tonight's dinner from your weekly plan.")
    /// Answered in place; there is nothing to look at.
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dinners = PlannedDinnerReader().upcoming()
        guard let today = dinners.first,
              Calendar.current.isDateInToday(today.date) else {
            return .result(dialog: IntentDialog(
                stringLiteral: L10n.string("There is no dinner planned for today yet.")
            ))
        }

        let line: String
        switch (today.isCooking, today.prepMinutes) {
        case (true, let minutes?):
            line = L10n.string("Tonight is %@, about %ld minutes.", today.title, minutes)
        default:
            line = L10n.string("Tonight: %@", today.title)
        }
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

struct MealShufflerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatIsForDinnerIntent(),
            phrases: [
                "What's for dinner in \(.applicationName)",
                "Ask \(.applicationName) what's for dinner",
                "\(.applicationName) dinner"
            ],
            shortTitle: "What's for dinner",
            systemImageName: "fork.knife"
        )
    }
}
