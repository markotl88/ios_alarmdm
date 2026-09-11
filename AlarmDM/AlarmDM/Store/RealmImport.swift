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

    private static let didRunKey = "didImportRealmIntoSwiftData"

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
            // import to it; carry the local state over rather than inserting
            // a second row for the same id.
            if let existing = try? existingEntity(with: podcast.id, in: context) {
                existing.isFavorite = row.isFavorite
                existing.fileUrl = row.fileUrl
            } else {
                let entity = PodcastEntity(from: podcast)
                entity.isFavorite = row.isFavorite
                entity.fileUrl = row.fileUrl
                context.insert(entity)
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
