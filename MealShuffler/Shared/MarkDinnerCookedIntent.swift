import AppIntents
import Foundation
import WidgetKit

/// "We cooked this", straight from the widget.
///
/// Compiled into both the app and the widget extension. A widget button runs this in the
/// widget's process, which has no `AppStore`: writing the app's state file from here would be
/// overwritten by the app's next save. So it leaves a note in the shared inbox for the app to
/// record, and ticks the day in the widget summary so the widget shows it straight away.
struct MarkDinnerCookedIntent: AppIntent {
    static var title: LocalizedStringResource = "We cooked this"
    static var description = IntentDescription("Marks the planned dinner as cooked.")
    /// Done in place; opening the app would defeat the point of the button.
    static var openAppWhenRun = false
    /// Only meaningful with a specific planned dinner, which the Shortcuts app cannot supply.
    static var isDiscoverable = false

    @Parameter(title: "Meal")
    var mealID: String

    @Parameter(title: "Day")
    var weekday: String

    /// The planned day, as seconds since 1970. AppIntents parameters cannot carry a `Weekday`
    /// or a `UUID` without making them app entities, which a button does not need.
    @Parameter(title: "Date")
    var date: Double

    init() {}

    init(mealID: UUID, day: Weekday, date: Date) {
        self.mealID = mealID.uuidString
        self.weekday = day.rawValue
        self.date = date.timeIntervalSince1970
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: mealID), let day = Weekday(rawValue: weekday) else {
            return .result()
        }
        let planned = Date(timeIntervalSince1970: date)
        WidgetActionInbox.add(WidgetActionInbox.CookedNote(mealID: id, day: day, date: planned))

        var summary = WidgetSummary.load()
        summary.cookedStamps.insert(WidgetSummary.stamp(for: planned))
        summary.save()

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
