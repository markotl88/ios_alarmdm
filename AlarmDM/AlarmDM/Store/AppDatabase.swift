//
//  AppDatabase.swift
//  AlarmDM
//
//  Owns the SwiftData stack.
//

import Foundation
import Combine
import CoreData
import SwiftData

final class AppDatabase {

    static let shared = AppDatabase()

    let container: ModelContainer

    /// True when the store could not be opened and the app is running against
    /// memory. Nothing is lost that matters — every episode comes back from
    /// the API — but favourites and downloads will not survive the session,
    /// and the repository should say so rather than pretend.
    private(set) var isEphemeral = false

    /// Deliberately not `container.mainContext`, which is @MainActor and would
    /// drag the annotation through the repository and everything that calls it.
    /// A context of our own is nonisolated, and this one is only ever touched
    /// from the main thread anyway — every write reaches it from a network
    /// completion that already hopped there.
    ///
    /// The trade is autosave: a hand-made context does not save on its own, so
    /// every write ends in an explicit `save()`. That suits this code, which
    /// suits this code, which has always written in explicit transactions.
    private(set) var context: ModelContext

    /// Fires when the store changed underneath us — which, now that half of
    /// it syncs, means another device wrote something. Screens hold snapshots
    /// they took when they appeared, so without this a bookmark made on the
    /// Mac sits in the database while the phone shows the old list and looks
    /// broken.
    ///
    /// SwiftData is Core Data underneath, and this is Core Data's notification
    /// for exactly this. If a future version stops posting it, nothing breaks:
    /// every screen still reads again when it appears or is pulled down.
    let didChangeRemotely = PassthroughSubject<Void, Never>()

    /// The iCloud container these devices share. One for both bundle ids, so
    /// a debug build on the phone and a release build on the Mac are looking
    /// at the same records — which is the only way to watch syncing work.
    static let cloudContainer = "iCloud.com.msorg.daskoimladja"

    /// What a person made: bookmarks, favourites, how far they got. Small,
    /// irreplaceable, and worth carrying between their devices.
    private static let syncedModels: [any PersistentModel.Type] =
        [BookmarkEntity.self, EpisodeStateEntity.self]

    /// What this device happens to hold: the feed cache and the downloaded
    /// files. Both are reproducible — one from the API, the other from the
    /// network — and a file path is a fact about one machine anyway.
    private static let localModels: [any PersistentModel.Type] =
        [PodcastEntity.self, DownloadEntity.self]

    /// `inMemory` is for tests, which want a store that starts empty and
    /// leaves nothing behind. It also turns syncing off: a test has no
    /// business reaching iCloud.
    init(inMemory: Bool = false) {
        let schema = Schema(AppDatabase.localModels + AppDatabase.syncedModels)
        isEphemeral = inMemory

        do {
            container = try ModelContainer(
                for: schema,
                configurations: AppDatabase.configurations(inMemory: inMemory, syncing: !inMemory)
            )
        } catch {
            // Most often this is iCloud refusing the schema — a model that
            // breaks one of CloudKit's rules, or an entitlement missing on a
            // build. Losing the whole database over that would be absurd when
            // the same store opens perfectly well unsynced, so try again
            // without it before giving up.
            debugPrint("SwiftData store unavailable, retrying without iCloud: \(error.localizedDescription)")

            do {
                container = try ModelContainer(
                    for: schema,
                    configurations: AppDatabase.configurations(inMemory: inMemory, syncing: false)
                )
            } catch {
                debugPrint("SwiftData store unavailable, running in memory: \(error.localizedDescription)")
                isEphemeral = true
                // If even an in-memory container cannot be built, the schema
                // itself is wrong — a programmer error, not a runtime
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
    }

    /// Throws away the context and takes a fresh one.
    ///
    /// A context is not a window onto the store, it is a copy of the part of
    /// it that has been looked at. Rows imported from iCloud land in the store
    /// underneath, and this context — made once at launch and kept for the
    /// life of the app — goes on answering with what it already held. That is
    /// what "every device only remembers its own state" looked like: the
    /// writing worked, the transport worked, and the reading was of a
    /// photograph taken before any of it arrived.
    ///
    /// Cheap: a context holds no data of its own until something is fetched
    /// through it.
    func adoptStoreChanges() {
        context = ModelContext(container)
        context.autosaveEnabled = false

        #if DEBUG
        debugPrint("store re-read")
        #endif
    }

    private func observeRemoteChanges() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.adoptStoreChanges()
            self.didChangeRemotely.send()
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
                debugPrint("cloud \(kind) started")
                return
            }

            if event.succeeded {
                debugPrint("cloud \(kind) finished")
            } else {
                debugPrint("cloud \(kind) failed: \(event.error?.localizedDescription ?? "-")")
            }
        }
        #endif
    }

    /// Two stores in one container: a context reaches both, and which one a
    /// row lands in is decided by its type.
    private static func configurations(inMemory: Bool, syncing: Bool) -> [ModelConfiguration] {
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
}
