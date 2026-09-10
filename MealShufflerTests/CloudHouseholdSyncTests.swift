import XCTest
@testable import MealShuffler

@MainActor
final class CloudHouseholdSyncTests: XCTestCase {
    func testUnsignedBuildKeepsSavedSharingPreferenceWithoutOpeningCloudKit() async throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "cloud-household-enabled")
        let sync = CloudHouseholdSync(defaults: defaults, isCloudKitAvailable: false)
        let store = AppStore(defaults: defaults, random: SeededRandomSource(seed: 7))
        let before = store.makeSnapshot()

        XCTAssertFalse(sync.enabled)
        XCTAssertNil(sync.sharingContainer)
        await sync.sync(store: store)
        await sync.start(store: store)
        await sync.acceptInvitation(store: store)
        await sync.prepareShare(store: store)
        await sync.resolve(useRemote: true, store: store)

        XCTAssertFalse(sync.enabled)
        XCTAssertFalse(sync.busy)
        XCTAssertNil(sync.share)
        XCTAssertNil(sync.pendingRemote)
        XCTAssertNotNil(sync.message)
        XCTAssertTrue(defaults.bool(forKey: "cloud-household-enabled"), "An unsigned run must not erase the signed app's preference")
        XCTAssertTrue(CloudHouseholdSync.equivalent(before, store.makeSnapshot()))
    }

    func testObservingPreviouslyEnabledSharingDoesNotCreateAContainer() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "cloud-household-enabled")
        // This host is unsigned in CI. An eager CKContainer initializer would trap here,
        // even though no sharing operation has been requested.
        let sync = CloudHouseholdSync(defaults: defaults, isCloudKitAvailable: true)
        XCTAssertTrue(sync.enabled)
        XCTAssertNil(sync.share)
        XCTAssertNil(sync.pendingRemote)
        XCTAssertFalse(sync.busy)
        sync.pause()
        XCTAssertFalse(sync.enabled)
    }

    func testIdleSyncDoesNotOpenCloudKitWhenSharingIsOff() async throws {
        let defaults = try makeDefaults()
        let sync = CloudHouseholdSync(defaults: defaults, isCloudKitAvailable: true)
        let store = AppStore(defaults: defaults, random: SeededRandomSource(seed: 7))

        await sync.sync(store: store)

        XCTAssertFalse(sync.enabled)
        XCTAssertFalse(sync.busy)
        XCTAssertNil(sync.message)
        XCTAssertNil(sync.lastSync)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "CloudHouseholdSyncTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}
