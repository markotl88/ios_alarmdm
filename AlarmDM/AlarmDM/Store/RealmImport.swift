//
//  RealmImport.swift
//  AlarmDM
//
//  A one-time copy from the Realm database into SwiftData. Runs once, on the
//  first launch after the update, and then never again.
//

import Foundation
import RealmSwift
import SwiftData

enum RealmImport {

    /// Version two of the key. Splitting the store into a synced half and a
    /// local one left the first SwiftData store behind — a development build
    /// that had already run the import would otherwise start empty and never
    /// try again, with the Realm file sitting right there.
    private static let didRunKey = "didImportRealmIntoSwiftData.v2"

    /// Copies only the rows the API cannot reproduce: favourites and episodes
    /// with a downloaded file. Everything else refills from the network on the
    /// very next fetch, and copying four thousand rows on the main thread at
    /// launch would stall the app for a list that is about to be replaced.
    ///
    /// Bookmarks are not copied. No shipped version ever wrote one, and the
    /// identifier changed shape — anything found would be from a development
    /// build.
    static func runIfNeeded(defaults: UserDefaults = .standard,
                            database: AppDatabase = .shared) {
        guard !defaults.bool(forKey: didRunKey) else { return }

        // An in-memory store means the real one failed to open. Marking the
        // import done would throw the favourites away for good, so leave the
        // flag alone and try again next launch.
        guard !database.isEphemeral else { return }

        guard let realm = try? Realm() else {
            // No Realm file at all is the normal case for a fresh install.
            defaults.set(true, forKey: didRunKey)
            return
        }

        let worthKeeping = realm.objects(PodcastRealm.self)
            .filter("isFavorite == true OR fileUrl != nil")

        guard !worthKeeping.isEmpty else {
            defaults.set(true, forKey: didRunKey)
            return
        }

        let context = database.context
        var imported = 0

        for row in worthKeeping {
            let podcast = Podcast(from: row)

            // The store may already hold the episode if a fetch beat the
            // import to it; do not insert a second row for the same id.
            let cached = (try? existingEntity(with: podcast.id, in: context)) ?? nil
            if cached == nil {
                context.insert(PodcastEntity(from: podcast))
            }

            // The favourite and the file are no longer part of the episode
            // row. One goes to the table that syncs, the other to the one that
            // stays here.
            if row.isFavorite {
                let state = EpisodeStateEntity(
                    podcastId: podcast.id,
                    title: podcast.title,
                    show: podcast.show.rawValue
                )
                state.isFavorite = true
                context.insert(state)
            }
            if let fileName = row.fileUrl {
                context.insert(DownloadEntity(podcastId: podcast.id, fileName: fileName))
            }
            imported += 1
        }

        do {
            try context.save()
            defaults.set(true, forKey: didRunKey)
            debugPrint("Imported \(imported) episodes from Realm")
        } catch {
            // Leave the flag unset so the next launch tries again.
            debugPrint("Realm import failed, will retry next launch: \(error.localizedDescription)")
        }
    }

    private static func existingEntity(with id: UUID, in context: ModelContext) throws -> PodcastEntity? {
        var descriptor = FetchDescriptor<PodcastEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
