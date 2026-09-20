//
//  PodcastRepository.swift
//  AlarmDM
//
//  The one place that reads and writes episodes. Used by the app, by the
//  CarPlay scene and by the view models, so the saving rules — stable ids,
//  preserved downloads — live in a single place.
//

import Foundation
import SwiftData

/// Reading one episode back out of the store. The player takes this rather
/// than the repository itself, so it can be given fixtures in a test instead
/// of whatever happens to be in the database.
protocol EpisodeLookup: AnyObject {
    func podcast(with id: UUID) -> Podcast?
    /// Forget what has already been read, in case something has arrived since.
    func refreshFromStore()
}

extension EpisodeLookup {
    func refreshFromStore() {}
}

final class PodcastRepository: EpisodeLookup {

    static let shared = PodcastRepository()

    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    private var context: ModelContext { database.context }

    /// Asked for by whoever is about to make a decision on what it reads back.
    func refreshFromStore() {
        database.adoptStoreChanges()
    }

    #if DEBUG
    /// Every row this device holds for one episode, as it holds them.
    ///
    /// The question this answers is the only one left: whether what another
    /// device wrote is in this database at all. If it is not, no amount of
    /// reading will find it and the problem is upstream of everything here.
    func describeState(for id: UUID) {
        let rows = fetchStates(matching: #Predicate { $0.podcastId == id })
        let total = (try? context.fetchCount(FetchDescriptor<EpisodeStateEntity>())) ?? -1

        AppLog.write(.store, "state rows for \(id): \(rows.count) — of \(total) in the store")
        for row in rows {
            AppLog.write(.store, "   \(Int(row.playedPosition))s at \(String(describing: row.playedAt)) fav:\(row.isFavorite)")
        }
    }
    #endif

    // MARK: - Reads

    func latestPodcasts(limit: Int = 10) -> [Podcast] {
        compose(fetch(limit: limit))
    }

    func podcasts(for show: Show, limit: Int = 200) -> [Podcast] {
        let raw = show.rawValue
        return compose(fetch(limit: limit, matching: #Predicate { $0.show == raw }))
    }

    /// Episodes a live bookmark could fall inside: the full cut, with a known
    /// broadcast time. Nothing else can host one.
    func broadcastEpisodes(limit: Int = 200) -> [Podcast] {
        compose(fetch(limit: limit, matching: #Predicate { $0.airedAt != nil && $0.isWithMusic }))
    }

    func podcast(with id: UUID) -> Podcast? {
        guard let entity = entity(with: id) else { return nil }
        return Podcast(from: entity, state: state(for: id), download: download(for: id))
    }

    /// The episode to offer as "carry on", or nil when there is nothing to
    /// carry on with: the most recent listen that has not finished.
    ///
    /// It looks at the listening rows rather than the episodes, because that
    /// is where the dates are, and it takes the first few rather than all of
    /// them — an episode heard a hundred listens ago is not what anyone means
    /// by continuing.
    func lastListened() -> Podcast? {
        refreshFromStore()

        let recent = fetchStates()
            .filter { $0.playedAt != nil && !$0.isPlayed }
            .sorted { EpisodeStateEntity.isNewer($0, than: $1) }
            .prefix(5)

        for state in recent {
            if let episode = podcast(with: state.podcastId), episode.resumePosition != nil {
                return episode
            }
        }
        return nil
    }

    /// Where this episode should start now, or nil to start at the beginning.
    ///
    /// Every way into playback has to ask this — the phone, the car, the lock
    /// screen — or the rules about where a listen resumes only hold on the
    /// screen they were written for. That is exactly how starting an episode
    /// from CarPlay went back to the beginning while the same episode on the
    /// phone carried on.
    ///
    /// It re-reads the store first, so a position that arrived from another
    /// device a moment ago is not missed by a copy taken at launch.
    func resumePosition(for id: UUID) -> TimeInterval? {
        refreshFromStore()
        return podcast(with: id)?.resumePosition
    }

    /// Puts an episode back together from the three rows that describe it: the
    /// feed's copy, what the person did with it, and whether it is on this
    /// device.
    ///
    /// Two queries for the whole page rather than two per episode — a list of
    /// two hundred would otherwise be four hundred round trips to the store
    /// for what is, in the end, a handful of matches.
    private func compose(_ entities: [PodcastEntity]) -> [Podcast] {
        guard !entities.isEmpty else { return [] }

        let ids = Set(entities.map(\.id))
        // Newest wins when an episode has more than one row; see merged(_:).
        // Reading is not the place to delete anything, so the duplicate is
        // simply passed over here and folded away the next time that episode
        // is written to.
        let states = Dictionary(
            fetchStates(matching: #Predicate { ids.contains($0.podcastId) }).map { ($0.podcastId, $0) },
            uniquingKeysWith: { EpisodeStateEntity.isNewer($0, than: $1) ? $0 : $1 }
        )
        let downloads = Dictionary(
            fetchDownloads(matching: #Predicate { ids.contains($0.podcastId) }).map { ($0.podcastId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return entities.map {
            Podcast(from: $0, state: states[$0.id], download: downloads[$0.id])
        }
    }

    // MARK: - Writes

    /// Upserts episodes. Nothing of the person's is at risk here any more:
    /// favourites, listening and downloads live in their own tables, so a
    /// feed refresh cannot tread on them.
    func save(_ podcasts: [Podcast]) {
        guard !podcasts.isEmpty else { return }

        // One fetch for the whole batch rather than one per episode: a page of
        // thirty episodes would otherwise mean thirty round trips to the store.
        let ids = Set(podcasts.map(\.id))
        let existing = Dictionary(
            fetch(matching: #Predicate { ids.contains($0.id) }).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for podcast in podcasts {
            if let entity = existing[podcast.id] {
                entity.apply(podcast)
            } else {
                context.insert(PodcastEntity(from: podcast))
            }
        }

        commit("saving episodes")
    }

    func save(_ podcast: Podcast) {
        save([podcast])
    }

    func setFavorite(_ isFavorite: Bool, for id: UUID) {
        state(for: id, creatingIfNeeded: true)?.isFavorite = isFavorite
        commit("updating favourite")
    }

    /// Writes down how far a listen got, and whether it went past the end of
    /// the show. Called when playback pauses and when the app goes away —
    /// never on a timer, for the same reason the player's own state is not
    /// saved on one: a second's accuracy would cost a write a second for the
    /// length of the episode.
    func recordProgress(position: TimeInterval, hasFinished: Bool, for id: UUID) {
        guard let state = state(for: id, creatingIfNeeded: true) else { return }
        state.playedPosition = max(0, position)
        // Sticky. Starting an episode again does not make it unfinished, and
        // an episode left at five minutes on a second device should not undo
        // the fact that it was heard through on the first.
        state.isPlayed = state.isPlayed || hasFinished
        state.playedAt = Date()
        commit("recording progress")

        #if DEBUG
        // The id is the thing to compare between two devices: the same episode
        // has to be the same id everywhere, or each device is writing into its
        // own corner of the same database and syncing looks broken.
        AppLog.write(.store, "progress \(Int(position))s for \(id) — \(state.episodeTitle)")
        #endif
    }

    func setDownloadedFile(_ fileName: String?, for id: UUID) {
        let existing = download(for: id)

        switch (fileName, existing) {
        case (let fileName?, let row?):
            row.fileName = fileName
            row.downloadedAt = Date()
        case (let fileName?, nil):
            context.insert(DownloadEntity(podcastId: id, fileName: fileName))
        case (nil, let row?):
            context.delete(row)
        case (nil, nil):
            return
        }

        commit("recording downloaded file")
    }

    func clearDownloadReference(for id: UUID) {
        setDownloadedFile(nil, for: id)
    }

    /// Forgets every download, after the files themselves are gone. Without
    /// this the app keeps claiming episodes are on the device.
    func clearAllDownloadReferences() {
        let rows = fetchDownloads()
        guard !rows.isEmpty else { return }
        for row in rows { context.delete(row) }
        commit("clearing download references")
    }

    // MARK: - Store access

    /// Newest first, like every list in the app. A nil `limit` means all of
    /// them.
    private func fetch(limit: Int? = nil,
                       matching predicate: Predicate<PodcastEntity>? = nil) -> [PodcastEntity] {
        var descriptor = FetchDescriptor<PodcastEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            return try context.fetch(descriptor)
        } catch {
            AppLog.write(.store, "Error reading episodes: \(error.localizedDescription)")
            return []
        }
    }

    private func entity(with id: UUID) -> PodcastEntity? {
        fetch(limit: 1, matching: #Predicate { $0.id == id }).first
    }

    private func fetchStates(matching predicate: Predicate<EpisodeStateEntity>? = nil) -> [EpisodeStateEntity] {
        do {
            return try context.fetch(FetchDescriptor<EpisodeStateEntity>(predicate: predicate))
        } catch {
            AppLog.write(.store, "Error reading episode state: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchDownloads(matching predicate: Predicate<DownloadEntity>? = nil) -> [DownloadEntity] {
        do {
            return try context.fetch(FetchDescriptor<DownloadEntity>(predicate: predicate))
        } catch {
            AppLog.write(.store, "Error reading downloads: \(error.localizedDescription)")
            return []
        }
    }

    /// The person's own row for an episode. Created on demand: most episodes
    /// never get one, and an empty row for every episode in the feed is
    /// exactly what this split was meant to avoid sending through iCloud.
    ///
    /// CloudKit allows no unique constraint, so two devices that both listen
    /// to an episode before either has heard of the other each create a row,
    /// and both rows then exist everywhere. Taking whichever came back first
    /// is how a device ends up reading its own old row forever with the other
    /// device's newer one sitting beside it — which looks exactly like syncing
    /// having stopped working.
    private func state(for id: UUID, creatingIfNeeded: Bool = false) -> EpisodeStateEntity? {
        let existing = fetchStates(matching: #Predicate { $0.podcastId == id })
        if !existing.isEmpty {
            return merged(existing)
        }
        guard creatingIfNeeded else { return nil }

        let episode = entity(with: id)
        let state = EpisodeStateEntity(
            podcastId: id,
            title: episode?.title ?? "",
            show: episode?.show
        )
        context.insert(state)
        return state
    }

    private func download(for id: UUID) -> DownloadEntity? {
        fetchDownloads(matching: #Predicate { $0.podcastId == id }).first
    }

    /// Folds duplicate rows for one episode into the newest of them and
    /// deletes the rest.
    ///
    /// The newest wins on position, because a position is a moment and the
    /// later moment is the true one. The two flags are OR-ed instead: an
    /// episode heard through on one device is heard, and a favourite marked
    /// on one device is a favourite, whatever the other device did later.
    @discardableResult
    private func merged(_ rows: [EpisodeStateEntity]) -> EpisodeStateEntity? {
        let sorted = rows.sorted { EpisodeStateEntity.isNewer($0, than: $1) }
        guard let winner = sorted.first else { return nil }
        guard sorted.count > 1 else { return winner }

        for duplicate in sorted.dropFirst() {
            winner.isFavorite = winner.isFavorite || duplicate.isFavorite
            winner.isPlayed = winner.isPlayed || duplicate.isPlayed
            if winner.episodeTitle.isEmpty { winner.episodeTitle = duplicate.episodeTitle }
            if winner.show == nil { winner.show = duplicate.show }
            context.delete(duplicate)
        }

        commit("merging duplicate episode state")
        return winner
    }

    /// A hand-made ModelContext does not autosave, so every change ends here.
    /// On failure the edits are rolled back rather than left sitting in the
    /// context, where the next successful save would carry them along.
    private func commit(_ what: String) {
        do {
            try context.save()
        } catch {
            AppLog.write(.store, "Error \(what): \(error.localizedDescription)")
            context.rollback()
        }
    }
}
