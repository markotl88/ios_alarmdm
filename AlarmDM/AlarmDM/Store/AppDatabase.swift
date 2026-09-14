//
//  AppDatabase.swift
//  AlarmDM
//
//  Owns the SwiftData stack.
//

import Foundation
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
    /// already wrote Realm in explicit transactions.
    let context: ModelContext

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
