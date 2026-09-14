//
//  RealmImport.swift
//  AlarmDM
//
//  A one-time copy from the Realm database into SwiftData. Runs once, on the
//  first launch after the update, and then never again.
//

import Foundation
import RealmSwift

/// A favourite or a download from the old database, waiting for the episode it
/// belongs to to arrive from the feed.
///
/// It is keyed by the media URL rather than by an id, and that is the whole
/// point of this type. The old app gave every episode a fresh random UUID, so
/// nothing in the Realm file can be matched against an episode from the API,
/// whose id is derived from the feed. The media URL is the one thing both
/// sides agree on.
private struct PendingLocalState: Codable {
    let podcastUrl: String
    let isFavorite: Bool
    let fileName: String?
}

enum RealmImport {

    private static let didRunKey = "didImportRealmIntoSwiftData.v3"
    private static let pendingKey = "pendingRealmLocalState"

    /// Copies only what the API cannot reproduce: which episodes were
    /// favourited and which were downloaded. Everything else refills from the
    /// network on the very next fetch.
    ///
    /// No episode rows are written here. Writing them would mean inventing an
    /// id for each — the old database has no usable one — and every invented
    /// id becomes a row the feed will never claim, carrying a favourite nobody
    /// can see. The state waits instead, and attaches itself to the real
    /// episode the moment that episode is fetched.
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
            .filter { !$0.podcastUrl.isEmpty }

        let pending = worthKeeping.map {
            PendingLocalState(podcastUrl: $0.podcastUrl,
                              isFavorite: $0.isFavorite,
                              fileName: $0.fileUrl)
        }

        save(pending, to: defaults)
        defaults.set(true, forKey: didRunKey)
        debugPrint("Carried \(pending.count) favourites and downloads over from Realm")

        // Whatever is already cached can be matched right away; the rest waits
        // for the next page of the feed.
        reconcile(with: PodcastRepository.shared.latestPodcasts(limit: 500), defaults: defaults)
    }

    /// Attaches whatever is still waiting to the episodes that have just
    /// arrived. Called after every save, and does nothing at all — one
    /// UserDefaults read — once the list is empty, which it is for every
    /// install that never had Realm.
    static func reconcile(with podcasts: [Podcast],
                          defaults: UserDefaults = .standard,
                          repository: PodcastRepository = .shared) {
        guard !podcasts.isEmpty else { return }

        var pending = load(from: defaults)
        guard !pending.isEmpty else { return }

        let byUrl = Dictionary(podcasts.map { ($0.podcastUrl, $0) },
                               uniquingKeysWith: { first, _ in first })
        var applied = 0

        pending.removeAll { entry in
            guard let episode = byUrl[entry.podcastUrl] else { return false }

            if entry.isFavorite {
                repository.setFavorite(true, for: episode.id)
            }
            if let fileName = entry.fileName {
                repository.setDownloadedFile(fileName, for: episode.id)
            }
            applied += 1
            return true
        }

        guard applied > 0 else { return }

        save(pending, to: defaults)
        debugPrint("Attached \(applied) carried-over episodes, \(pending.count) still waiting")
        EpisodeLibrary.shared.episodeDidChange()
    }

    // MARK: - The waiting list

    private static func load(from defaults: UserDefaults) -> [PendingLocalState] {
        guard let data = defaults.data(forKey: pendingKey) else { return [] }
        return (try? JSONDecoder().decode([PendingLocalState].self, from: data)) ?? []
    }

    private static func save(_ pending: [PendingLocalState], to defaults: UserDefaults) {
        guard !pending.isEmpty else {
            defaults.removeObject(forKey: pendingKey)
            return
        }
        guard let data = try? JSONEncoder().encode(pending) else { return }
        defaults.set(data, forKey: pendingKey)
    }
}
