import Foundation

enum FeatureFlags {
    /// Community is backed by three seeded local families, a rating that syncs nowhere, and a
    /// share sheet whose invitation link only opens an alert saying sync is not built.
    ///
    /// Shipping that as one of five primary tabs costs more trust than leaving it out, and
    /// polishing it would only make the impression better executed. Turn on together with the
    /// identity and moderation work: publishing, rating and reporting are all unsafe while
    /// anyone can act as anyone.
    static let communityEnabled = false

    /// The invitation link and code describe a sync that does not exist: following one opens
    /// an alert saying so. The household model, tombstones and `updatedBy` stamps are all in
    /// place for it -- turn this on with the backend that answers them.
    static let householdSyncEnabled = false
}
