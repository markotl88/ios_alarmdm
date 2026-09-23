//
//  AppDatabase.swift
//  AlarmDM
//
//  Owns the SwiftData stack.
//

import Foundation
import Combine
import CloudKit
import CoreData
import SwiftData

final class AppDatabase {

    static let shared = AppDatabase()

    let container: ModelContainer

    /// True when the store could not be opened and the app is running against
    /// memory. Nothing is lost that matters - every episode comes back from
    /// the API - but favourites and downloads will not survive the session,
    /// and the repository should say so rather than pretend.
    private(set) var isEphemeral = false

    /// Deliberately not `container.mainContext`, which is @MainActor and would
    /// drag the annotation through the repository and everything that calls it.
    /// A context of our own is nonisolated, and this one is only ever touched
    /// from the main thread anyway - every write reaches it from a network
    /// completion that already hopped there.
    ///
    /// The trade is autosave: a hand-made context does not save on its own, so
    /// every write ends in an explicit `save()`. That suits this code, which
    /// suits this code, which has always written in explicit transactions.
    private(set) var context: ModelContext

    /// Fires when the store changed underneath us - which, now that half of
    /// it syncs, means another device wrote something. Screens hold snapshots
    /// they took when they appeared, so without this a bookmark made on the
    /// Mac sits in the database while the phone shows the old list and looks
    /// broken.
    ///
    /// SwiftData is Core Data underneath, and this is Core Data's notification
    /// for exactly this. If a future version stops posting it, nothing breaks:
    /// every screen still reads again when it appears or is pulled down.
    /// Debounced: bringing up iCloud posts this dozens of times in a couple
    /// of seconds - forty of them in five, on a fresh install - and every one
    /// would send every open screen back to the store for a list it already
    /// has. What the screens need to know is that something arrived, not how
    /// many times it arrived.
    var didChangeRemotely: AnyPublisher<Void, Never> {
        storeChanged
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    private let storeChanged = PassthroughSubject<Void, Never>()

    /// The iCloud container these devices share. One for both bundle ids, so
    /// a debug build on the phone and a release build on the Mac are looking
    /// at the same records - which is the only way to watch syncing work.
    static let cloudContainer = "iCloud.com.msorg.daskoimladja"

    /// What a person made: bookmarks, favourites, how far they got. Small,
    /// irreplaceable, and worth carrying between their devices.
    static let syncedModels: [any PersistentModel.Type] =
        [BookmarkEntity.self, EpisodeStateEntity.self]

    /// What this device happens to hold: the feed cache and the downloaded
    /// files. Both are reproducible - one from the API, the other from the
    /// network - and a file path is a fact about one machine anyway.
    static let localModels: [any PersistentModel.Type] =
        [PodcastEntity.self, DownloadEntity.self]

    /// `inMemory` is for tests, which want a store that starts empty and
    /// leaves nothing behind. `storeDirectory` is for the tests that need the
    /// store to be a file two containers can open at once - which is what an
    /// import from iCloud looks like from inside the app: something else
    /// writing to the same store. Either one turns syncing off: a test has no
    /// business reaching iCloud.
    init(inMemory: Bool = false, storeDirectory: URL? = nil) {
        let schema = Schema(AppDatabase.localModels + AppDatabase.syncedModels)
        let syncing = !inMemory && storeDirectory == nil
        isEphemeral = inMemory

        do {
            container = try ModelContainer(
                for: schema,
                configurations: AppDatabase.configurations(inMemory: inMemory, syncing: syncing, directory: storeDirectory)
            )
        } catch {
            // Most often this is iCloud refusing the schema - a model that
            // breaks one of CloudKit's rules, or an entitlement missing on a
            // build. Losing the whole database over that would be absurd when
            // the same store opens perfectly well unsynced, so try again
            // without it before giving up.
            AppLog.write(.sync, "SwiftData store unavailable, retrying without iCloud: \(error.localizedDescription)")

            do {
                container = try ModelContainer(
                    for: schema,
                    configurations: AppDatabase.configurations(inMemory: inMemory, syncing: false, directory: storeDirectory)
                )
            } catch {
                AppLog.write(.sync, "SwiftData store unavailable, running in memory: \(error.localizedDescription)")
                isEphemeral = true
                // If even an in-memory container cannot be built, the schema
                // itself is wrong - a programmer error, not a runtime
                // condition, and there is nothing sensible left to fall back
                // to.
                container = try! ModelContainer(
                    for: schema,
                    configurations: AppDatabase.configurations(inMemory: true, syncing: false)
                )
            }
        }

        context = ModelContext(container)
        context.autosaveEnabled = false

        observeRemoteChanges()

        #if DEBUG
        if syncing { describeAccount() }
        #endif
    }

    #if DEBUG
    /// Which iCloud account this device is syncing as.
    ///
    /// Two devices exporting happily and neither ever seeing the other is
    /// exactly what two different accounts look like: each writes to its own
    /// private database, every export succeeds, and every import brings back
    /// only what that account already had. The user record id is the same
    /// string on two devices signed in to the same account, and a different
    /// one otherwise - which makes it the one line that settles it.
    private func describeAccount() {
        let container = CKContainer(identifier: AppDatabase.cloudContainer)

        container.accountStatus { status, error in
            let name: String
            switch status {
            case .available: name = "available"
            case .noAccount: name = "no account"
            case .restricted: name = "restricted"
            case .couldNotDetermine: name = "could not determine"
            case .temporarilyUnavailable: name = "temporarily unavailable"
            @unknown default: name = "unknown"
            }
            AppLog.write(.sync, "icloud account: \(name)\(error.map { " - \($0.localizedDescription)" } ?? "")")
        }

        container.fetchUserRecordID { id, error in
            AppLog.write(.sync, "icloud user: \(id?.recordName ?? "none")\(error.map { " - \($0.localizedDescription)" } ?? "")")
        }
    }
    #endif

    #if DEBUG
    /// Everything this app has ever stored, gone - the rows on this device and
    /// the zone in iCloud that would otherwise put them back.
    ///
    /// Deleting the app is not enough and never was. The synced half lives in
    /// the private database, and a reinstalled app finds it there and imports
    /// it within seconds, which is why "I deleted both apps" kept producing a
    /// store that already knew where the episode had stopped.
    ///
    /// The zone goes first. Emptying the tables first would queue a pile of
    /// deletions for a zone that is about to stop existing, and every one of
    /// them has to be waited for.
    ///
    /// One device at a time is not enough either: another device still holding
    /// rows will export them into the fresh zone at its next launch. All of
    /// them have to be cleared before any of them is started again.
    func eraseEverything() async -> [String] {
        var report: [String] = []

        let zone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone",
                                   ownerName: CKCurrentUserDefaultName)
        let database = CKContainer(identifier: AppDatabase.cloudContainer).privateCloudDatabase

        do {
            _ = try await database.modifyRecordZones(saving: [], deleting: [zone])
            report.append("iCloud: zona obrisana")
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            report.append("iCloud: zone nije ni bilo")
        } catch {
            report.append("iCloud: \(error.localizedDescription)")
        }

        do {
            try context.delete(model: BookmarkEntity.self)
            try context.delete(model: EpisodeStateEntity.self)
            try context.delete(model: PodcastEntity.self)
            try context.delete(model: DownloadEntity.self)
            try context.save()
            report.append("baza: sve tabele ispražnjene")
        } catch {
            report.append("baza: \(error.localizedDescription)")
        }

        adoptStoreChanges()
        AppLog.write(.sync, "erased everything - \(report.joined(separator: "; "))")
        return report
    }
    #endif

    /// Throws away the context and takes a fresh one.
    ///
    /// A precaution, not a fix. It was written on the theory that a context
    /// kept for the life of the app goes on answering with rows it read before
    /// an import changed them, and that this was why each device seemed to
    /// remember only its own state. StoreChangeTests says otherwise: the
    /// repository hands out copies and fetches on every read, so nothing it
    /// read earlier is still held, and a second writer's change is seen
    /// without this. What was actually wrong then was upstream - the other
    /// device's row had not arrived at all.
    ///
    /// It stays because it costs nothing - a context holds no data until
    /// something is fetched through it - and because it keeps that true if
    /// something ever does start holding on to rows.
    func adoptStoreChanges() {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    private func observeRemoteChanges() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.adoptStoreChanges()
            self.storeChanged.send()
        }

        #if DEBUG
        // Syncing is otherwise completely silent, which makes "it did not
        // arrive" impossible to tell apart from "it has not arrived yet" and
        // from "it was refused". Every import and export announces itself
        // here, with whatever went wrong when something did.
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }

            let kind: String
            switch event.type {
            case .setup: kind = "setup"
            case .import: kind = "import"
            case .export: kind = "export"
            @unknown default: kind = "event"
            }

            guard event.endDate != nil else {
                AppLog.write(.sync, "cloud \(kind) started")
                return
            }

            if event.succeeded {
                AppLog.write(.sync, "cloud \(kind) finished")
            } else {
                AppLog.write(.sync, "cloud \(kind) failed: \(event.error?.localizedDescription ?? "-")")
            }
        }
        #endif
    }

    /// Two stores in one container: a context reaches both, and which one a
    /// row lands in is decided by its type.
    private static func configurations(inMemory: Bool, syncing: Bool, directory: URL? = nil) -> [ModelConfiguration] {
        if let directory, !inMemory {
            return [
                ModelConfiguration("Local", schema: Schema(localModels),
                                   url: directory.appendingPathComponent("Local.store"),
                                   cloudKitDatabase: .none),
                ModelConfiguration("Synced", schema: Schema(syncedModels),
                                   url: directory.appendingPathComponent("Synced.store"),
                                   cloudKitDatabase: syncing ? .private(cloudContainer) : .none),
            ]
        }

        let local = ModelConfiguration(
            "Local",
            schema: Schema(localModels),
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )

        let synced = ModelConfiguration(
            "Synced",
            schema: Schema(syncedModels),
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: syncing ? .private(cloudContainer) : .none
        )

        return [local, synced]
    }

    /// The synced half exactly as the app opens it - same models, same iCloud
    /// container - at a place of the caller's choosing. For the test that
    /// asks whether iCloud will accept the schema, which is a question only
    /// opening the store answers.
    static func syncedConfiguration(at url: URL) -> ModelConfiguration {
        ModelConfiguration("Synced", schema: Schema(syncedModels), url: url,
                           cloudKitDatabase: .private(cloudContainer))
    }
}
