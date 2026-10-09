import ActivityKit
import Foundation

/// The cook-mode timer on the lock screen and in the Dynamic Island.
///
/// Compiled into both the app, which starts and ends the activity, and the widget extension,
/// which draws it. Local only: the app updates it directly and nothing is pushed.
struct CookingTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the timer runs out.
        var endsAt: Date
        /// The step being cooked, e.g. "Step 2 of 5: Fry the onions", when the recipe has steps.
        var stepText: String?
    }

    var mealName: String
    var emoji: String
}
