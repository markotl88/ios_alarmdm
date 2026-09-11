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

    private init() {
        let schema = Schema([PodcastEntity.self, BookmarkEntity.self])

        do {
            container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            )
        } catch {
            debugPrint("SwiftData store unavailable, running in memory: \(error.localizedDescription)")
            isEphemeral = true
            // If even an in-memory container cannot be built, the schema itself
            // is wrong — a programmer error, not a runtime condition, and there
            // is nothing sensible left to fall back to.
            container = try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }

        context = ModelContext(container)
        context.autosaveEnabled = false
    }
}
