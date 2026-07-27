import Foundation

enum Weekday: String, CaseIterable, Codable, Identifiable, Hashable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: String { rawValue }

    var name: String {
        switch self {
        case .monday: "Mandag"
        case .tuesday: "Tirsdag"
        case .wednesday: "Onsdag"
        case .thursday: "Torsdag"
        case .friday: "Fredag"
        case .saturday: "Lørdag"
        case .sunday: "Søndag"
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
