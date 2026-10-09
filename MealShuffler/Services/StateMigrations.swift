import Foundation

/// Upgrades a saved state blob to the current schema before it is decoded.
///
/// Adding a field never needs this: `decodeIfPresent` defaults cover it. A change that
/// *reinterprets* data does -- moving a key, splitting one value into two, changing what a
/// number means -- and doing that inside `init(from:)` mixes every version's rules into one
/// decoder until nobody can tell which branch serves which blob. Here each step is one
/// version to the next, run in order on plain JSON, and each can be tested on its own.
///
/// Every path that reads a snapshot -- the state file, its backup copy, the widget, a device
/// backup, a shared household -- goes through `AppStateSnapshot.decoding(_:)`, so a step
/// written here applies everywhere at once.
enum StateMigrations {
    typealias JSONObject = [String: Any]

    struct Step {
        /// The version this step upgrades *from*; it leaves the blob at `from + 1`.
        let from: Int
        let migrate: (inout JSONObject) -> Void
    }

    /// In order. The last step's `from + 1` must equal `AppStateSnapshot.currentVersion`.
    static let steps: [Step] = [
        // 1 -> 2: taste was one flat map for the household. It belongs to the owner, the only
        // person the swipe screen could have been speaking for.
        //
        // JSONEncoder writes a dictionary keyed by UUID as a flat array -- key, value, key,
        // value -- so both the old map and the new one are arrays here, not objects.
        Step(from: 1) { object in
            guard object["memberPreferences"] == nil,
                  let flat = object["preferences"] as? [Any], !flat.isEmpty else { return }
            let household = object["household"] as? JSONObject
            let members = household?["members"] as? [JSONObject] ?? []
            let owner = members.first { $0["role"] as? String == HouseholdRole.owner.rawValue }?["id"]
                ?? members.first?["id"]
                ?? household?["id"]
            guard let ownerID = owner as? String else { return }
            object["memberPreferences"] = [ownerID, flat] as [Any]
            object["preferences"] = nil
        },
        // 2 -> 3 and 3 -> 4 only added fields, which decode with defaults.
        Step(from: 2) { _ in },
        Step(from: 3) { _ in }
    ]

    /// The blob at the current version, or the input unchanged when it is not a JSON object,
    /// is already current, or comes from a newer app (the decoder refuses that one with a
    /// message rather than this guessing at it).
    static func migrate(_ data: Data) -> Data {
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject else { return data }
        var version = object["schemaVersion"] as? Int ?? 1
        guard version < AppStateSnapshot.currentVersion else { return data }
        // Ascending, so each step finds the version the one before it left.
        for step in steps where step.from == version {
            step.migrate(&object)
            version = step.from + 1
        }
        object["schemaVersion"] = version
        return (try? JSONSerialization.data(withJSONObject: object)) ?? data
    }
}

extension AppStateSnapshot {
    /// Decodes a saved blob of any supported version.
    static func decoding(_ data: Data) throws -> AppStateSnapshot {
        try JSONDecoder().decode(AppStateSnapshot.self, from: StateMigrations.migrate(data))
    }
}
