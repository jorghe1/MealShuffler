import Foundation

enum Weekday: String, CaseIterable, Codable, Identifiable, Hashable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: String { rawValue }

    var name: String {
        switch self {
        case .monday: L10n.string("Monday")
        case .tuesday: L10n.string("Tuesday")
        case .wednesday: L10n.string("Wednesday")
        case .thursday: L10n.string("Thursday")
        case .friday: L10n.string("Friday")
        case .saturday: L10n.string("Saturday")
        case .sunday: L10n.string("Sunday")
        }
    }

    var shortName: String { Weekday.shortSymbol(for: self) }

    /// The next day in the locale's week, or nil on the last day.
    var next: Weekday? {
        let ordered = Weekday.ordered()
        guard let index = ordered.firstIndex(of: self), index < ordered.count - 1 else { return nil }
        return ordered[index + 1]
    }
}
