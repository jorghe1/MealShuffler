import CloudKit
import Combine
import Foundation
import SwiftUI

/// Uses CloudKit's server change tags. Concurrent edits always require a choice; an
/// offline device never unconditionally saves over a household's newer version.
@MainActor final class CloudHouseholdSync: ObservableObject {
    static let shared = CloudHouseholdSync()
    static let containerIdentifier = "iCloud.no.mealshuffler"
    // CKContainer can trap before XCTest attaches when this host is unsigned. Observing
    // the service must stay local; only an allowed CloudKit operation creates a container.
    private lazy var container = CKContainer(identifier: CloudHouseholdSync.containerIdentifier)
    let isCloudKitAvailable: Bool
    @Published private(set) var busy = false
    @Published var message: String?
    @Published private(set) var pendingRemote: AppStateSnapshot?
    @Published var share: CKShare?
    @Published private(set) var enabled: Bool
    @Published private(set) var lastSync: Date?
    private var pendingRecord: CKRecord?
    private var incomingShare: CKShare.Metadata?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, isCloudKitAvailable: Bool? = nil) {
        let available = isCloudKitAvailable
            ?? ((Bundle.main.object(forInfoDictionaryKey: "CloudKitSigningAllowed") as? String) == "YES")
        self.defaults = defaults
        self.isCloudKitAvailable = available
        enabled = available && defaults.bool(forKey: "cloud-household-enabled")
    }

    var sharingContainer: CKContainer? {
        guard isCloudKitAvailable else { return nil }
        return container
    }

    private func requireCloudKit() -> Bool {
        guard isCloudKitAvailable else {
            message = L10n.string("iCloud sharing is unavailable in this unsigned build. Your local household data is still available.")
            return false
        }
        return true
    }
    private var isParticipant: Bool { defaults.bool(forKey: "cloud-household-participant") }
    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: defaults.string(forKey: "cloud-household-zone") ?? "MealShufflerHousehold",
                        ownerName: defaults.string(forKey: "cloud-household-owner") ?? CKCurrentUserDefaultName)
    }
    private var database: CKDatabase { isParticipant ? container.sharedCloudDatabase : container.privateCloudDatabase }
    private var rootID: CKRecord.ID { CKRecord.ID(recordName: "household", zoneID: zoneID) }
    private var baselineURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("icloud-baseline.json")
    }
    private var baseline: AppStateSnapshot? {
        guard let data = try? Data(contentsOf: baselineURL) else { return nil }
        return try? JSONDecoder().decode(AppStateSnapshot.self, from: data)
    }
    private func remember(_ state: AppStateSnapshot) throws {
        try FileManager.default.createDirectory(at: baselineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: baselineURL, options: .atomic)
        lastSync = .now
    }

    func received(_ metadata: CKShare.Metadata) {
        guard requireCloudKit() else { return }
        incomingShare = metadata
        message = L10n.string("An iCloud invitation is ready. Open iCloud sharing to review it.")
    }
    var hasInvitation: Bool { incomingShare != nil }

    func acceptInvitation(store: AppStore) async {
        guard requireCloudKit() else { return }
        guard let metadata = incomingShare, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            guard metadata.containerIdentifier == Self.containerIdentifier else { throw CocoaError(.fileReadCorruptFile) }
            try DeviceBackupDocument.retainRecovery(store.makeSnapshot())
            _ = try await container.accept(metadata)
            defaults.set(metadata.rootRecordID.zoneID.zoneName, forKey: "cloud-household-zone")
            defaults.set(metadata.rootRecordID.zoneID.ownerName, forKey: "cloud-household-owner")
            defaults.set(true, forKey: "cloud-household-participant")
            defaults.set(true, forKey: "cloud-household-enabled"); enabled = true
            try? FileManager.default.removeItem(at: baselineURL)
            incomingShare = nil
            let record = try await database.record(for: rootID)
            pendingRemote = try decode(record); pendingRecord = record
            message = L10n.string("Review the shared household before replacing this device's data.")
        } catch { message = error.localizedDescription }
    }

    func start(store: AppStore) async {
        guard requireCloudKit() else { return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            guard try await container.accountStatus() == .available else {
                message = L10n.string("Sign in to iCloud in iOS Settings to share a household."); return
            }
            if !isParticipant { _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: zoneID)) }
            defaults.set(true, forKey: "cloud-household-enabled"); enabled = true
            busy = false
            await sync(store: store)
        } catch { message = error.localizedDescription }
    }

    func pause() {
        enabled = false; defaults.set(false, forKey: "cloud-household-enabled")
        message = L10n.string("Sync is paused on this device. Shared data remains in iCloud.")
    }

    func sync(store: AppStore) async {
        guard isCloudKitAvailable, enabled, !busy, pendingRemote == nil else { return }
        busy = true
        defer { busy = false }
        do {
            let local = store.makeSnapshot()
            let record: CKRecord
            do { record = try await database.record(for: rootID) }
            catch let error as CKError where error.code == .unknownItem && !isParticipant {
                // A missing existing household may mean its owner removed it: never recreate it silently.
                guard baseline == nil else { throw error }
                let created = CKRecord(recordType: "Household", recordID: rootID)
                try await upload(local, record: created); try remember(local); message = nil; return
            }
            let remote = try decode(record)
            if Self.equivalent(local, remote) {
                try await downloadImages(remote)
                try await ensureImages(local)
                try remember(remote); message = nil; return
            }
            if let baseline, Self.equivalent(remote, baseline) {
                try await upload(local, record: record); try remember(local); message = nil
            } else if let baseline, Self.equivalent(local, baseline) {
                try await downloadImages(remote)
                // The user may have edited while the network request was in flight.
                guard Self.equivalent(store.makeSnapshot(), local) else {
                    pendingRemote = remote; pendingRecord = record; return
                }
                try store.restoreSnapshot(remote, sharedOnly: true); try remember(remote); message = nil
            } else {
                pendingRemote = remote; pendingRecord = record
                message = L10n.string("This device and iCloud have different changes. Choose which household version to keep. A recovery copy is saved first.")
            }
        } catch { message = error.localizedDescription }
    }

    func resolve(useRemote: Bool, store: AppStore) async {
        guard requireCloudKit() else { return }
        guard let remote = pendingRemote, let record = pendingRecord, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let local = store.makeSnapshot()
            try DeviceBackupDocument.retainRecovery(local)
            if useRemote {
                try await downloadImages(remote)
                guard Self.equivalent(store.makeSnapshot(), local) else { message = L10n.string("The household changed while syncing. Review it again."); return }
                try store.restoreSnapshot(remote, sharedOnly: true); try remember(remote)
            } else {
                // Retain the losing remote version too, including its images.
                try await downloadImages(remote)
                try DeviceBackupDocument.retainRecovery(remote)
                try await upload(local, record: record); try remember(local)
            }
            pendingRemote = nil; pendingRecord = nil; message = nil
        } catch {
            pendingRemote = nil; pendingRecord = nil
            message = error.localizedDescription
        }
    }

    func prepareShare(store: AppStore) async {
        guard requireCloudKit() else { return }
        guard enabled, pendingRemote == nil, !busy else { return }
        await sync(store: store)
        guard pendingRemote == nil, message == nil else { return }
        busy = true
        defer { busy = false }
        do {
            let root = try await database.record(for: rootID)
            if let reference = root.share {
                share = try await database.record(for: reference.recordID) as? CKShare
            } else {
                let created = CKShare(rootRecord: root)
                created[CKShare.SystemFieldKey.title] = store.household.name as CKRecordValue
                created.publicPermission = .none
                let result = try await database.modifyRecords(saving: [root, created], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
                for saved in result.saveResults.values { _ = try saved.get() }
                share = try await database.record(for: created.recordID) as? CKShare
            }
        } catch { message = error.localizedDescription }
    }

    private func decode(_ record: CKRecord) throws -> AppStateSnapshot {
        guard let asset = record["state"] as? CKAsset, let url = asset.fileURL,
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 100_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        let snapshot = try JSONDecoder().decode(AppStateSnapshot.self, from: Data(contentsOf: url))
        guard snapshot.customMeals.count <= 2000, snapshot.plan.meals.count <= 7 else { throw CocoaError(.fileReadCorruptFile) }
        return snapshot
    }

    private func imageNames(_ state: AppStateSnapshot) -> Set<String> {
        Set((state.customMeals + state.archivedWeeks.flatMap { $0.recipeSnapshots ?? [] } + state.feedbackEvents.compactMap(\.recipeSnapshot) + state.tools.freezer.map(\.recipe) + (state.plan.meals + (state.nextWeekPlan?.meals ?? []) + state.archivedWeeks.flatMap { $0.plan.meals }).compactMap { $0.freezerBatch?.recipe })
            .flatMap { $0.sourceImageNames ?? [] })
    }
    private func downloadImages(_ state: AppStateSnapshot) async throws {
        for name in imageNames(state) {
            guard RecipeLibraryStorage.isSourceImageName(name) else { throw CocoaError(.fileReadCorruptFile) }
            if RecipeLibraryStorage.image(named: name) != nil { continue }
            let record = try await database.record(for: CKRecord.ID(recordName: name, zoneID: zoneID))
            guard let asset = record["image"] as? CKAsset, let url = asset.fileURL,
                  (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 2_000_000 else { throw CocoaError(.fileReadCorruptFile) }
            try RecipeLibraryStorage.restoreImages([name: Data(contentsOf: url)])
        }
    }
    private func upload(_ state: AppStateSnapshot, record: CKRecord) async throws {
        let isNew = record.recordChangeTag == nil
        if !isNew { try await ensureImages(state) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var transport = state
        transport.tools.cooking = [:]
        transport.dinnerReminderEnabled = false; transport.prepLeadReminderEnabled = false
        transport.groceryReminderEnabled = false; transport.dinnerReminderHour = 18
        transport.groceryReminderHour = 10; transport.groceryReminderWeekday = .saturday
        try JSONEncoder().encode(transport).write(to: url, options: .atomic)
        record["state"] = CKAsset(fileURL: url)
        let results = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        for saved in results.saveResults.values { _ = try saved.get() }
        if isNew { try await ensureImages(state) }
    }

    private func ensureImages(_ state: AppStateSnapshot) async throws {
        for name in imageNames(state) {
            guard RecipeLibraryStorage.isSourceImageName(name) else { throw CocoaError(.fileReadCorruptFile) }
            let id = CKRecord.ID(recordName: name, zoneID: zoneID)
            do { _ = try await database.record(for: id); continue }
            catch let error as CKError where error.code == .unknownItem { }
            guard RecipeLibraryStorage.image(named: name) != nil else { throw CocoaError(.fileNoSuchFile) }
            let image = CKRecord(recordType: "RecipeImage", recordID: id)
            image.parent = CKRecord.Reference(recordID: rootID, action: .none)
            image["image"] = CKAsset(fileURL: RecipeLibraryStorage.directory.appendingPathComponent(name))
            let result = try await database.modifyRecords(saving: [image], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
            for saved in result.saveResults.values { _ = try saved.get() }
        }
    }

    nonisolated static func equivalent(_ a: AppStateSnapshot, _ b: AppStateSnapshot) -> Bool {
        guard a.customMeals == b.customMeals, a.rules == b.rules, a.plan == b.plan,
              a.nextWeekPlan == b.nextWeekPlan, a.dayContexts == b.dayContexts, a.nextWeekContexts == b.nextWeekContexts else { return false }
        guard a.checkedGroceryIDs == b.checkedGroceryIDs, a.stockedGroceryIDs == b.stockedGroceryIDs,
              a.manualGroceryItems == b.manualGroceryItems, a.pantryStaples == b.pantryStaples, a.aisleOrder == b.aisleOrder else { return false }
        guard a.household == b.household, a.householdSize == b.householdSize, a.memberPreferences == b.memberPreferences,
              a.favoriteMealIDs == b.favoriteMealIDs, a.feedbackEvents == b.feedbackEvents, a.archivedWeeks == b.archivedWeeks else { return false }
        var left = a.tools; var right = b.tools; left.cooking = [:]; right.cooking = [:]
        return left == right
    }
}

struct CloudSharingView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var sync = CloudHouseholdSync.shared
    var body: some View {
        List {
            Section {
                Text("Share recipes, plans, shopping progress and household preferences with invited iCloud users. Everyone can edit. Cooking steps and notification settings stay personal.")
                if !sync.isCloudKitAvailable {
                    Text("iCloud sharing is unavailable in this unsigned build. Your local household data is still available.")
                }
                if sync.hasInvitation { Button("Accept iCloud invitation") { Task { await sync.acceptInvitation(store: store) } } }
                if sync.enabled {
                    Button("Sync now") { Task { await sync.sync(store: store) } }
                    Button("Invite or manage people") { Task { await sync.prepareShare(store: store) } }
                    Button("Pause on this device") { sync.pause() }
                } else { Button("Enable iCloud sharing") { Task { await sync.start(store: store) } } }
                if let date = sync.lastSync { LabeledContent("Last synced", value: date.formatted(date: .abbreviated, time: .shortened)) }
            }.disabled(sync.busy || !sync.isCloudKitAvailable)
            if let remote = sync.pendingRemote {
                Section("Review iCloud changes") {
                    Text(L10n.string("Shared household: %@", remote.household.name))
                    Text(WeekAnchor.label(forWeekStarting: remote.plan.startDate))
                    Text(L10n.string("%ld shared recipes", remote.customMeals.count))
                    DisclosureGroup("Shared plan and shopping") {
                        Text(PlanTextExporter.weeklyPlan(remote.plan, meals: MealCatalog.resolve(custom: remote.customMeals)))
                        Text(PlanTextExporter.groceryList(GroceryListBuilder.build(plan: remote.plan, meals: MealCatalog.resolve(custom: remote.customMeals), manualItems: remote.manualGroceryItems).filter { !remote.checkedGroceryIDs.contains($0.id) && !remote.stockedGroceryIDs.contains($0.id) }))
                    }
                    DisclosureGroup("This device's plan and shopping") {
                        Text(PlanTextExporter.weeklyPlan(store.plan, meals: store.meals))
                        Text(PlanTextExporter.groceryList(store.groceryItems.filter { !store.checkedGroceryIDs.contains($0.id) }))
                    }
                    Button("Use shared version") { Task { await sync.resolve(useRemote: true, store: store) } }
                    Button("Keep this device's version") { Task { await sync.resolve(useRemote: false, store: store) } }
                }.disabled(sync.busy)
            }
            if sync.busy { ProgressView() }
            if let message = sync.message { Text(message).textSelection(.enabled) }
        }.navigationTitle("iCloud sharing")
        .sheet(isPresented: Binding(get: { sync.share != nil }, set: { if !$0 { sync.share = nil } })) {
            if let share = sync.share, let container = sync.sharingContainer {
                CloudShareController(share: share, container: container)
            }
        }
    }
}

private struct CloudShareController: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) { }
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func itemTitle(for controller: UICloudSharingController) -> String? { "Meal Shuffler" }
        func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: Error) {
            Task { @MainActor in CloudHouseholdSync.shared.message = error.localizedDescription }
        }
    }
}
