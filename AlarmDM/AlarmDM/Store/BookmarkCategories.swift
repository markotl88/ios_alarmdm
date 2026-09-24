//
//  BookmarkCategories.swift
//  AlarmDM
//
//  The one place the category list is read and written. Screens observe it
//  rather than asking the store while they draw.
//

import Foundation
import Combine
import SwiftData

/// The arranged list, kept current.
///
/// An object rather than a function because every screen that shows
/// categories needs the same answer at the same time, and because a category
/// made on one device has to turn up on another without anybody reopening
/// anything - `didChangeRemotely` is what says it arrived.
final class BookmarkCategories: ObservableObject {

    static let shared = BookmarkCategories()

    @Published private(set) var items: [BookmarkCategoryItem] = []

    private let database: AppDatabase
    private var cancellables = Set<AnyCancellable>()

    init(database: AppDatabase = .shared) {
        self.database = database
        reload()

        database.didChangeRemotely
            .sink { [weak self] in self?.reload() }
            .store(in: &cancellables)
    }

    private var context: ModelContext { database.context }

    func reload() {
        items = BookmarkCatalog.arranged(rows())
    }

    /// The category a bookmark's stored id points at, or nil when it has none
    /// and when it points at one that has since been deleted.
    func item(id: String?) -> BookmarkCategoryItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    /// Only the ones actually in use, for a filter - a filter that can only
    /// ever return nothing is a dead end.
    func items(usedBy bookmarks: [Bookmark]) -> [BookmarkCategoryItem] {
        let used = Set(bookmarks.compactMap(\.categoryId))
        return items.filter { used.contains($0.id) }
    }

    // MARK: - Writes

    /// Makes one of theirs and hands back its id, so the bookmark being
    /// written can be filed under it in the same breath.
    @discardableResult
    func add(name: String, iconName: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let id = UUID().uuidString
        context.insert(BookmarkCategoryEntity(id: id,
                                              name: trimmed,
                                              iconName: iconName,
                                              sortOrder: BookmarkCatalog.orderAfter(items),
                                              isBuiltIn: false,
                                              editedAt: Date()))
        commit("adding a category")
        return id
    }

    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let row = merged(id), !row.isBuiltIn else { return }
        row.name = trimmed
        row.editedAt = Date()
        commit("renaming a category")
    }

    /// Only one of theirs. A built-in is part of the app and cannot be taken
    /// out of it; the bookmarks filed under one they made keep their id and
    /// simply stop resolving, which reads as having no category.
    func delete(_ id: String) {
        guard BookmarkCategory(rawValue: id) == nil else { return }
        for row in rows() where row.id == id { context.delete(row) }
        commit("deleting a category")
    }

    /// The whole list in its new order, ids first to last. Every one gets a
    /// row, built-ins included: once it has been arranged by hand the shipped
    /// order stops being the answer.
    func rearrange(toOrder ids: [String]) {
        let positions = BookmarkCatalog.positions(forNewOrder: ids)
        let now = Date()

        for (id, order) in positions {
            if let row = merged(id) {
                row.sortOrder = order
                row.editedAt = now
            } else if let builtIn = BookmarkCategory(rawValue: id) {
                context.insert(BookmarkCategoryEntity(id: builtIn.rawValue,
                                                      sortOrder: order,
                                                      isBuiltIn: true,
                                                      editedAt: now))
            }
        }
        commit("rearranging the categories")
    }

    // MARK: - Store access

    private func rows() -> [BookmarkCategoryEntity] {
        (try? context.fetch(FetchDescriptor<BookmarkCategoryEntity>())) ?? []
    }

    /// The row for an id, folding duplicates into the newest of them and
    /// deleting the rest - the same thing PodcastRepository.merged does, and
    /// for the same reason: two devices can each have written one.
    private func merged(_ id: String) -> BookmarkCategoryEntity? {
        let matching = rows().filter { $0.id == id }
            .sorted { BookmarkCategoryEntity.isNewer($0, than: $1) }
        guard let winner = matching.first else { return nil }
        for duplicate in matching.dropFirst() { context.delete(duplicate) }
        return winner
    }

    private func commit(_ what: String) {
        do {
            try context.save()
            reload()
        } catch {
            AppLog.write(.store, "Error \(what): \(error.localizedDescription)")
            context.rollback()
        }
    }
}
