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

    /// iCloud household sharing (`CloudHouseholdSync`, `CloudSharingView`).
    ///
    /// Off for the first public release. The sync works, but it moves the whole household as
    /// one JSON asset polled every 30 seconds, resolves conflicts for the whole household at
    /// once -- two people ticking groceries in the shop get "choose a version" -- and has not
    /// had its two-account acceptance run (docs/ICLOUD_SHARING.md). When this is false the
    /// sharing screens are hidden, the 30-second poll does not run and an invitation that
    /// arrives anyway is not acted on. Turn on together with per-entity records and push.
    static let householdSyncEnabled = false
}
