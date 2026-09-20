//
//  BookmarkRepository.swift
//  AlarmDM
//
//  The one place that reads and writes bookmarks.
//

import Foundation
import SwiftData

final class BookmarkRepository {

    static let shared = BookmarkRepository()

    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    private var context: ModelContext { database.context }

    // MARK: - Reads

    /// Newest first — a bookmark is something you come back to soon after
    /// making it, far more often than months later.
    func all() -> [Bookmark] {
        fetch().map(Bookmark.init(from:))
    }

    func bookmarks(for category: BookmarkCategory) -> [Bookmark] {
        let raw = category.rawValue
        return fetch(matching: #Predicate { $0.category == raw }).map(Bookmark.init(from:))
    }

    var isEmpty: Bool {
        (try? context.fetchCount(FetchDescriptor<BookmarkEntity>())) ?? 0 == 0
    }

    // MARK: - Writes

    func add(_ bookmark: Bookmark) {
        // The episode is named by id, and the title is copied either way — so
        // a bookmark reads correctly on a device whose cache has never seen
        // the episode, which is now a normal state rather than an edge case.
        context.insert(BookmarkEntity(from: bookmark, podcastId: bookmark.podcastId))
        commit("saving bookmark")
    }

    /// Moves a live capture into the episode it fell inside. The title and
    /// show are rewritten too — until now they said "Radio uživo", which was
    /// true and is no longer.
    func link(_ id: UUID, to episode: Podcast, position: TimeInterval) {
        guard let entity = entity(with: id) else { return }
        entity.podcastId = episode.id
        entity.position = position
        entity.episodeTitle = episode.title
        entity.show = episode.show.rawValue
        commit("linking bookmark to its episode")
    }

    /// Used when a corrected broadcast time moves a live capture that was
    /// already placed.
    func setPosition(_ position: TimeInterval, for id: UUID) {
        guard let entity = entity(with: id) else { return }
        entity.position = position
        commit("moving bookmark")
    }

    func setCategory(_ category: BookmarkCategory?, for id: UUID) {
        guard let entity = entity(with: id) else { return }
        entity.category = category?.rawValue
        commit("updating bookmark category")
    }

    func setNote(_ note: String, for id: UUID) {
        guard let entity = entity(with: id) else { return }
        entity.note = note
        commit("updating bookmark note")
    }

    func delete(_ id: UUID) {
        guard let entity = entity(with: id) else { return }
        context.delete(entity)
        commit("deleting bookmark")
    }

    // MARK: - Store access

    private func fetch(limit: Int? = nil,
                       matching predicate: Predicate<BookmarkEntity>? = nil) -> [BookmarkEntity] {
        var descriptor = FetchDescriptor<BookmarkEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            return try context.fetch(descriptor)
        } catch {
            AppLog.write(.store, "Error reading bookmarks: \(error.localizedDescription)")
            return []
        }
    }

    private func entity(with id: UUID) -> BookmarkEntity? {
        fetch(limit: 1, matching: #Predicate { $0.id == id }).first
    }

    private func commit(_ what: String) {
        do {
            try context.save()
        } catch {
            AppLog.write(.store, "Error \(what): \(error.localizedDescription)")
            context.rollback()
        }
    }
}
