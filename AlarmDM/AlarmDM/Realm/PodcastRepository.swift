//
//  PodcastRepository.swift
//  AlarmDM
//
//  The one place that reads and writes podcasts in Realm. Used by the app,
//  by the CarPlay scene and by the view models, so saving rules (stable ids,
//  preserved downloads) live in a single place.
//

import Foundation
import RealmSwift

final class PodcastRepository {

    static let shared = PodcastRepository()

    private var realm: Realm? { try? Realm() }

    // MARK: - Reads

    func latestPodcasts(limit: Int = 10) -> [Podcast] {
        guard let realm else {
            debugPrint("Realm unavailable, returning no podcasts")
            return []
        }
        let results = realm.objects(PodcastRealm.self)
            .sorted(byKeyPath: "createdAt", ascending: false)
        return Array(results.prefix(limit)).map { Podcast(from: $0) }
    }

    func podcasts(for show: Show, limit: Int = 200) -> [Podcast] {
        guard let realm else { return [] }
        let results = realm.objects(PodcastRealm.self)
            .filter("show == %@", show.rawValue)
            .sorted(byKeyPath: "createdAt", ascending: false)
        return Array(results.prefix(limit)).map { Podcast(from: $0) }
    }

    func podcast(with id: UUID) -> Podcast? {
        guard let realm,
              let object = realm.objects(PodcastRealm.self)
                .filter("id == %@", id.uuidString).first else { return nil }
        return Podcast(from: object)
    }

    // MARK: - Writes

    /// Upserts episodes, keeping any local state (downloaded file, favourite)
    /// that the incoming API objects know nothing about.
    func save(_ podcasts: [Podcast]) {
        guard let realm, !podcasts.isEmpty else { return }

        do {
            try realm.write {
                for podcast in podcasts {
                    var podcast = podcast
                    if let existing = realm.object(ofType: PodcastRealm.self, forPrimaryKey: podcast.id.uuidString) {
                        podcast.fileUrl = existing.fileUrl
                        podcast.isFavorite = existing.isFavorite
                    }
                    realm.add(PodcastRealm(from: podcast), update: .modified)
                }
            }
        } catch {
            debugPrint("Error saving podcasts to Realm: \(error.localizedDescription)")
        }
    }

    func save(_ podcast: Podcast) {
        save([podcast])
    }

    func setFavorite(_ isFavorite: Bool, for id: UUID) {
        guard let realm,
              let object = realm.object(ofType: PodcastRealm.self, forPrimaryKey: id.uuidString) else { return }
        do {
            try realm.write { object.isFavorite = isFavorite }
        } catch {
            debugPrint("Error updating favourite: \(error.localizedDescription)")
        }
    }

    /// Clears the local file reference on every row, after the files themselves
    /// are gone. Without this the app keeps claiming episodes are downloaded.
    func clearAllDownloadReferences() {
        guard let realm else { return }
        do {
            try realm.write {
                for object in realm.objects(PodcastRealm.self).filter("fileUrl != nil") {
                    object.fileUrl = nil
                }
            }
        } catch {
            debugPrint("Error clearing download references: \(error.localizedDescription)")
        }
    }

}
