//
//  PodcastRepository.swift
//  AlarmDM
//
//  The one place that reads and writes podcasts in Realm. Used by the app,
//  by the CarPlay scene and by the view models, so saving rules (stable ids,
//  preserved downloads) live in a single place.
//

import Foundation
import Combine
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

    func clearDownloadReference(for id: UUID) {
        guard let realm,
              let object = realm.object(ofType: PodcastRealm.self, forPrimaryKey: id.uuidString) else { return }
        do {
            try realm.write { object.fileUrl = nil }
        } catch {
            debugPrint("Error clearing download reference: \(error.localizedDescription)")
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

// MARK: - Episode actions

/// Favouriting and deleting a download touch both the file system and Realm,
/// and both the Radio tab and a show's list offer them. Kept in one place so
/// the two screens cannot drift apart.
final class EpisodeLibrary {

    static let shared = EpisodeLibrary()

    /// Fires whenever an episode's local state changes. Lists hold snapshots
    /// taken from Realm when they appeared, so without this a download made
    /// from the player leaves every visible row still claiming it is not
    /// downloaded — and the Preuzeto filter cannot see it.
    let didChange = PassthroughSubject<Void, Never>()

    private let repository = PodcastRepository.shared
    private let fileService: FileServiceProtocol

    init(fileService: FileServiceProtocol = FileService()) {
        self.fileService = fileService
    }

    /// Called by whoever wrote to Realm outside this type — the player, after
    /// a download finishes.
    func episodeDidChange() {
        didChange.send()
    }

    func toggleFavourite(_ podcast: Podcast) {
        repository.setFavorite(!podcast.isFavorite, for: podcast.id)
        didChange.send()
    }

    /// Deleting while the episode is playing is safe: the player holds the file
    /// open and keeps reading it until it is done.
    @discardableResult
    func deleteDownload(_ podcast: Podcast) -> Bool {
        guard let fileName = podcast.fileUrl else { return false }

        switch fileService.deleteFile(with: fileName) {
        case .success:
            repository.clearDownloadReference(for: podcast.id)
            didChange.send()
            return true
        case .failure(let error):
            debugPrint("Error deleting download: \(error.localizedDescription)")
            return false
        }
    }
}
