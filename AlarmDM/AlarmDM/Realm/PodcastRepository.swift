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

    func setDownloadedFile(_ fileName: String?, for id: UUID) {
        guard let realm,
              let object = realm.object(ofType: PodcastRealm.self, forPrimaryKey: id.uuidString) else { return }
        do {
            try realm.write { object.fileUrl = fileName }
        } catch {
            debugPrint("Error recording downloaded file: \(error.localizedDescription)")
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

    /// Fires when the WiFi-only rule stopped a download, so the UI can offer to
    /// go ahead anyway or to drop the rule. The library refuses rather than
    /// deciding for the person — it has no way to ask.
    let downloadBlocked = PassthroughSubject<Podcast, Never>()

    private let repository = PodcastRepository.shared
    private let fileService: FileServiceProtocol
    private let podcastService: PodcastServiceProtocol
    private let settings = AppSettings.shared
    private let network = NetworkMonitor.shared

    /// Episodes with a download in flight. A row shows a ring for these, and a
    /// second tap cannot start the same download twice.
    private(set) var downloadsInFlight: Set<UUID> = []

    private var downloadProgress: [UUID: Double] = [:]
    private let progressSubject = PassthroughSubject<(id: UUID, progress: Double), Never>()

    /// Progress ticks, one stream for the whole app. Every consumer filters by
    /// episode id, so a row redraws only for its own download and the list is
    /// never rebuilt for someone else's.
    var progressPublisher: AnyPublisher<(id: UUID, progress: Double), Never> {
        progressSubject.eraseToAnyPublisher()
    }

    func progress(for id: UUID) -> Double { downloadProgress[id] ?? 0 }

    init(fileService: FileServiceProtocol = FileService(),
         podcastService: PodcastServiceProtocol = PodcastService()) {
        self.fileService = fileService
        self.podcastService = podcastService
    }

    func isDownloading(_ podcast: Podcast) -> Bool {
        downloadsInFlight.contains(podcast.id)
    }

    /// Downloads an episode and records the local file. `didChange` fires when
    /// the download starts and when it ends — never per tick, so a list is not
    /// rebuilt sixty times a minute; progress goes out on `progressPublisher`
    /// instead. On a metered connection this refuses and emits `downloadBlocked`
    /// unless `force` says the person has already chosen.
    ///
    /// Returns whether the download actually started, so a caller does not put
    /// itself into a downloading state for something that was refused.
    @discardableResult
    func download(_ podcast: Podcast,
                  force: Bool = false,
                  completion: ((Result<URL, Error>) -> Void)? = nil) -> Bool {
        guard !podcast.isDownloaded else { return false }
        guard !downloadsInFlight.contains(podcast.id) else { return false }
        guard let url = URL(string: podcast.podcastUrl) else {
            debugPrint("Episode \(podcast.id) has no usable media URL")
            return false
        }

        if !force, settings.downloadsOverWiFiOnly, network.isMetered {
            downloadBlocked.send(podcast)
            return false
        }

        downloadsInFlight.insert(podcast.id)
        downloadProgress[podcast.id] = 0
        didChange.send()

        podcastService.downloadPodcasts(from: url, completion: { [weak self] result in
            guard let self else { return }
            self.downloadsInFlight.remove(podcast.id)
            self.downloadProgress[podcast.id] = nil

            if case .success(let location) = result {
                self.repository.setDownloadedFile(location.lastPathComponent, for: podcast.id)
            } else if case .failure(let error) = result {
                debugPrint("Error downloading episode: \(error.localizedDescription)")
            }

            self.didChange.send()
            completion?(result)
        }, progressHandler: { [weak self] value in
            guard let self else { return }
            // Throttled to whole percent steps, and hopped to main because the
            // session reports progress from its own queue.
            DispatchQueue.main.async {
                let previous = self.downloadProgress[podcast.id] ?? 0
                guard value >= previous + 0.01 || value >= 1 else { return }
                self.downloadProgress[podcast.id] = value
                self.progressSubject.send((id: podcast.id, progress: value))
            }
        })

        return true
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
