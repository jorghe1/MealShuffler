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

    var shortName: String { String(name.prefix(3)) }

    var next: Weekday? {
        guard let index = Self.allCases.firstIndex(of: self), index < Self.allCases.count - 1 else {
            return nil
        }
        return Self.allCases[index + 1]
    }
}
