import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let mealShufflerBackup = UTType(exportedAs: "no.mealshuffler.backup", conformingTo: .package)
}

/// Files remain separate so photos never expand into base64 inside a huge JSON document.
struct DeviceBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.mealShufflerBackup] }
    static let maximumBytes = 500_000_000
    let state: AppStateSnapshot
    let files: [String: Data]

    init(state: AppStateSnapshot, files: [String: Data]) throws {
        // A decoded snapshot is repaired already; this one may come straight from memory.
        var state = state
        state.repairOutOfRangeValues()
        self.state = state; self.files = files
        try validate()
    }

    init(configuration: ReadConfiguration) throws { try self.init(wrapper: configuration.file) }

    init(wrapper: FileWrapper) throws {
        guard let children = wrapper.fileWrappers, children.count == 2,
              let data = children["state.json"]?.regularFileContents, data.count <= 100_000_000,
              let assets = children["files"]?.fileWrappers, assets.count <= 20_000 else { throw CocoaError(.fileReadCorruptFile) }
        state = try AppStateSnapshot.decoding(data)
        var restored: [String: Data] = [:]
        var total = data.count
        for (name, file) in assets {
            guard let contents = file.regularFileContents, Self.validName(name) else { throw CocoaError(.fileReadCorruptFile) }
            total += contents.count
            guard total <= Self.maximumBytes else { throw CocoaError(.fileReadTooLarge) }
            restored[name] = contents
        }
        files = restored
        try validate()
    }

    func validate() throws {
        try state.validateStructure()
        let stateBytes = try JSONEncoder().encode(state).count
        // The shape of the state itself is `validateStructure`'s job, above; only sizes here.
        guard stateBytes <= 100_000_000, files.count <= 20_000, files.keys.allSatisfy(Self.validName),
              files.values.reduce(0, { $0 + $1.count }) + stateBytes <= Self.maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        let photos = Dictionary(uniqueKeysWithValues: files.filter { $0.key.hasPrefix("library__source-") }.map { (String($0.key.dropFirst(9)), $0.value) })
        try RecipeLibraryArchive(meals: state.customMeals, images: photos).validate()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { try wrapper() }

    func wrapper() throws -> FileWrapper {
        try validate()
        return FileWrapper(directoryWithFileWrappers: [
            "state.json": FileWrapper(regularFileWithContents: try JSONEncoder().encode(state)),
            "files": FileWrapper(directoryWithFileWrappers: files.mapValues { FileWrapper(regularFileWithContents: $0) })
        ])
    }

    static func preflight(_ url: URL) throws {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        let root = try url.resourceValues(forKeys: keys)
        guard root.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
        var total = root.fileSize ?? 0
        if root.isDirectory == true {
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { throw CocoaError(.fileReadCorruptFile) }
            var count = 0
            for case let file as URL in enumerator {
                count += 1
                let values = try file.resourceValues(forKeys: keys)
                guard values.isSymbolicLink != true, count <= 20_010 else { throw CocoaError(.fileReadCorruptFile) }
                if values.isRegularFile == true { total += values.fileSize ?? 0 }
                guard total <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
            }
        }
        guard total <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
    }

    static func validName(_ name: String) -> Bool {
        name == URL(fileURLWithPath: name).lastPathComponent && !name.contains("\\") && !name.contains("..")
            && ["library__", "inbox__", "images__"].contains(where: { name.hasPrefix($0) })
    }

    static var roots: [String: URL] {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ["library__": RecipeLibraryStorage.directory,
                "inbox__": root.appendingPathComponent("RecipeInbox"),
                "images__": root.appendingPathComponent("SharedRecipeImages")]
    }

    static func capture(_ state: AppStateSnapshot) throws -> Self {
        var files: [String: Data] = [:]
        var total = 0
        for (prefix, directory) in roots {
            for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])) ?? [] {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, url.pathExtension == "json" || url.pathExtension == "jpg" || url.pathExtension == "img" else { continue }
                total += values.fileSize ?? 0
                guard total <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
                files[prefix + url.lastPathComponent] = try Data(contentsOf: url)
            }
        }
        return try Self(state: state, files: files)
    }

    /// Puts the backup in place: files first, then the state, and the files back out again
    /// if the state cannot be saved.
    ///
    /// The files used to be written and left whatever happened next, so a restore whose state
    /// failed to save -- a full disk, a file from a newer app -- left this device's household
    /// with the backup's photos and drafts in place of its own. Files still go first because
    /// the restore re-reads the recipe inbox, which has to find the backup's captures there.
    @MainActor
    func restore(into store: AppStore, roots: [String: URL] = DeviceBackupDocument.roots) throws {
        let placed = try restoreFiles(into: roots)
        do { try store.restoreSnapshot(state) } catch {
            placed.rollBack()
            throw error
        }
        placed.commit()
    }

    /// Writes every file into place, keeping each one it replaces until the caller commits
    /// or rolls back.
    func restoreFiles(into roots: [String: URL] = DeviceBackupDocument.roots) throws -> RestoredFiles {
        try validate()
        // Every name is resolved before anything on disk is touched.
        var targets: [(destination: URL, root: URL, data: Data)] = []
        for (name, data) in files {
            guard let entry = roots.first(where: { name.hasPrefix($0.key) }) else { throw CocoaError(.fileReadCorruptFile) }
            targets.append((entry.value.appendingPathComponent(String(name.dropFirst(entry.key.count))), entry.value, data))
        }
        let placed = RestoredFiles()
        do {
            // All staged before any is moved, so running out of space fails here, while every
            // original is still where it was.
            var staged: [(file: URL, destination: URL, scratch: URL)] = []
            for target in targets {
                let scratch = try placed.scratch(for: target.root)
                let file = scratch.appendingPathComponent("new-" + target.destination.lastPathComponent)
                try target.data.write(to: file, options: .atomic)
                staged.append((file, target.destination, scratch))
            }
            for item in staged { try placed.move(item.file, into: item.destination, asideIn: item.scratch) }
        } catch {
            placed.rollBack()
            throw error
        }
        return placed
    }

    @discardableResult static func retainRecovery(_ state: AppStateSnapshot) throws -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Recovery")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("before-restore-\(UUID()).mealbackup")
        try capture(state).wrapper().write(to: url, options: .atomic, originalContentsURL: nil)
        pruneRecovery(in: root, keeping: recoveryKept)
        return url
    }

    /// Recovery packages hold every photo, and one is written per restore -- two per iCloud
    /// conflict kept local, one for each side. At three, two conflict resolutions in a row
    /// pushed out the copy taken before a full restore, which is the one most worth having.
    static let recoveryKept = 10

    static func pruneRecovery(in root: URL, keeping count: Int) {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        let packages = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys)) ?? [])
            .filter { $0.pathExtension == "mealbackup" }
            .map { url -> (url: URL, date: Date) in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return (url: url, date: values?.creationDate ?? values?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.date > $1.date }
        for package in packages.dropFirst(count) {
            try? FileManager.default.removeItem(at: package.url)
        }
    }
}

/// A restore's files: in place, but revocable until the state they belong to is saved.
///
/// Every file a restore replaces is moved aside rather than overwritten, into a scratch
/// folder beside its own so each move is a rename on the same volume. `commit()` throws the
/// originals away; `rollBack()` puts them back and removes what the restore added.
final class RestoredFiles {
    private var scratchByRoot: [URL: URL] = [:]
    /// Originals moved aside: where they lived, and where they are now.
    private var replaced: [(original: URL, aside: URL)] = []
    /// Files that did not exist before the restore.
    private var added: [URL] = []

    fileprivate func scratch(for root: URL) throws -> URL {
        if let existing = scratchByRoot[root] { return existing }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let scratch = root.deletingLastPathComponent()
            .appendingPathComponent(".restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        scratchByRoot[root] = scratch
        return scratch
    }

    fileprivate func move(_ file: URL, into destination: URL, asideIn scratch: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            let aside = scratch.appendingPathComponent("old-" + destination.lastPathComponent)
            try manager.moveItem(at: destination, to: aside)
            replaced.append((destination, aside))
        } else {
            added.append(destination)
        }
        try manager.moveItem(at: file, to: destination)
    }

    /// The restore stands: the originals are no longer needed.
    func commit() {
        removeScratch()
        replaced = []; added = []
    }

    /// The restore failed: every file is as it was before it began.
    func rollBack() {
        let manager = FileManager.default
        for url in added { try? manager.removeItem(at: url) }
        for item in replaced.reversed() {
            try? manager.removeItem(at: item.original)
            try? manager.moveItem(at: item.aside, to: item.original)
        }
        removeScratch()
        replaced = []; added = []
    }

    private func removeScratch() {
        for scratch in scratchByRoot.values { try? FileManager.default.removeItem(at: scratch) }
        scratchByRoot = [:]
    }
}

struct DeviceBackupView: View {
    @Environment(AppStore.self) private var store
    @State private var exporting = false
    @State private var importing = false
    @State private var document: DeviceBackupDocument?
    @State private var pending: DeviceBackupDocument?
    @State private var message: String?
    @State private var busy = false
    @State private var recoveryFiles: [URL] = []
    var body: some View {
        List {
            Section {
                Button("Export full backup") {
                    busy = true
                    let snapshot = store.makeSnapshot()
                    Task {
                        do { document = try await Task.detached { try DeviceBackupDocument.capture(snapshot) }.value; exporting = true }
                        catch { message = error.localizedDescription }
                        busy = false
                    }
                }.disabled(busy)
                Button("Restore full backup") { importing = true }.disabled(busy)
                Text("Includes plans, rules, household preferences, shopping progress, recipes, drafts, source photos, history and freezer batches. Restoring replaces household data on this device and keeps a recovery copy first.")
            }
            Text("Existing local drafts and captures are kept when restoring a backup.").font(.caption)
            Section("Recovery copies") {
                ForEach(recoveryFiles, id: \.self) { url in
                    ShareLink(item: url) { Text(url.lastPathComponent) }
                }
            }
            if busy { ProgressView() }
            if let message { Text(message) }
        }.navigationTitle("Full backups")
        .task { loadRecovery() }
        .fileExporter(isPresented: $exporting, document: document, contentType: .mealShufflerBackup, defaultFilename: "Meal-Shuffler.mealbackup") { if case .failure(let error) = $0 { message = error.localizedDescription } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.mealShufflerBackup]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                try DeviceBackupDocument.preflight(url)
                pending = try DeviceBackupDocument(wrapper: FileWrapper(url: url, options: []))
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("Replace this device's household data?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Restore backup", role: .destructive) {
                guard let pending else { return }
                do {
                    try DeviceBackupDocument.retainRecovery(store.makeSnapshot())
                    try pending.restore(into: store)
                    message = L10n.string("Backup restored."); loadRecovery()
                } catch { message = error.localizedDescription }
                self.pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        }
    }
    private func loadRecovery() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Recovery")
        recoveryFiles = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    }
}
