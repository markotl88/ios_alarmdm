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

final class PodcastRepository {

    static let shared = PodcastRepository()

    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    private var context: ModelContext { database.context }

    // MARK: - Reads

    func latestPodcasts(limit: Int = 10) -> [Podcast] {
        fetch(limit: limit).map(Podcast.init(from:))
    }

    func podcasts(for show: Show, limit: Int = 200) -> [Podcast] {
        let raw = show.rawValue
        return fetch(limit: limit, matching: #Predicate { $0.show == raw })
            .map(Podcast.init(from:))
    }

    func podcast(with id: UUID) -> Podcast? {
        entity(with: id).map(Podcast.init(from:))
    }

    // MARK: - Writes

    /// Upserts episodes, keeping the local state the incoming API objects know
    /// nothing about — the downloaded file and the favourite flag.
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
        guard let entity = entity(with: id) else { return }
        entity.isFavorite = isFavorite
        commit("updating favourite")
    }

    func setDownloadedFile(_ fileName: String?, for id: UUID) {
        guard let entity = entity(with: id) else { return }
        entity.fileUrl = fileName
        commit("recording downloaded file")
    }

    func clearDownloadReference(for id: UUID) {
        setDownloadedFile(nil, for: id)
    }

    /// Clears the local file reference on every row, after the files
    /// themselves are gone. Without this the app keeps claiming episodes are
    /// downloaded.
    func clearAllDownloadReferences() {
        let withFiles = fetch(matching: #Predicate { $0.fileUrl != nil })
        guard !withFiles.isEmpty else { return }
        for entity in withFiles { entity.fileUrl = nil }
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
            debugPrint("Error reading episodes: \(error.localizedDescription)")
            return []
        }
    }

    private func entity(with id: UUID) -> PodcastEntity? {
        fetch(limit: 1, matching: #Predicate { $0.id == id }).first
    }

    /// A hand-made ModelContext does not autosave, so every change ends here.
    /// On failure the edits are rolled back rather than left sitting in the
    /// context, where the next successful save would carry them along.
    private func commit(_ what: String) {
        do {
            try context.save()
        } catch {
            debugPrint("Error \(what): \(error.localizedDescription)")
            context.rollback()
        }
    }
}
