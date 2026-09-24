//
//  BookmarksViewModel.swift
//  AlarmDM
//

import Foundation
import Combine

final class BookmarksViewModel: ObservableObject {

    @Published private(set) var bookmarks: [Bookmark] = []
    /// The episodes behind these bookmarks that this device is holding,
    /// worked out once per load - see canOpen.
    @Published private(set) var playableEpisodeIds: Set<UUID> = []
    /// nil means every category, including the ones with none set.
    @Published var activeCategoryId: String?

    private let library: BookmarkLibrary
    private let podcasts: PodcastRepository
    private let categories: BookmarkCategories
    private var cancellables = Set<AnyCancellable>()

    init(library: BookmarkLibrary = .shared,
         podcasts: PodcastRepository = .shared,
         categories: BookmarkCategories = .shared) {
        self.library = library
        self.podcasts = podcasts
        self.categories = categories
        reload()

        library.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reload() }
            .store(in: &cancellables)

        // A category made on another device changes what these rows say
        // about themselves, without any bookmark having changed.
        categories.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func reload() {
        // An episode published since the last look may now hold a bookmark
        // that was caught live. Does nothing unless one is waiting.
        library.reconcileLiveCaptures()
        bookmarks = library.all()
        playableEpisodeIds = podcasts.existingEpisodeIds(among: Set(bookmarks.compactMap(\.podcastId)))
    }

    var visibleBookmarks: [Bookmark] {
        guard let activeCategoryId else { return bookmarks }
        return bookmarks.filter { $0.categoryId == activeCategoryId }
    }

    /// Only offer the categories that are actually in use - a filter that can
    /// only ever return nothing is a dead end.
    var availableCategories: [BookmarkCategoryItem] {
        categories.items(usedBy: bookmarks)
    }

    /// What to draw on a row, or nil when it has no category and when it
    /// points at one that has since been deleted.
    func category(of bookmark: Bookmark) -> BookmarkCategoryItem? {
        categories.item(id: bookmark.categoryId)
    }

    /// Everything, for the menu that sets a bookmark's category.
    var allCategories: [BookmarkCategoryItem] { categories.items }

    var isEmpty: Bool { bookmarks.isEmpty }

    // MARK: - Actions

    func setCategory(_ categoryId: String?, for bookmark: Bookmark) {
        library.setCategory(categoryId, for: bookmark.id)
    }

    func delete(_ bookmark: Bookmark) {
        library.delete(bookmark.id)
        if activeCategoryId != nil && visibleBookmarks.isEmpty { activeCategoryId = nil }
    }

    /// The episode behind a bookmark, when the store still holds it. A live
    /// capture never has one, and a cached row can have been replaced.
    func episode(for bookmark: Bookmark) -> Podcast? {
        guard let podcastId = bookmark.podcastId else { return nil }
        return podcasts.podcast(with: podcastId)
    }

    /// Whether a tap on this one will play anything.
    ///
    /// Bookmarks sync and the episodes do not: a bookmark made on the phone
    /// arrives on a Mac that has never fetched that episode, and the lookup
    /// finds nothing. The row used to promise a play triangle and then do
    /// nothing at all when pressed; it now says what it is - a note - until
    /// the episode turns up in this device's own list.
    ///
    /// A lookup in a set worked out when the list loaded. Asking the store
    /// here would mean three fetches for every row, every time the list is
    /// drawn - and it is drawn again on every tick of the player.
    func canOpen(_ bookmark: Bookmark) -> Bool {
        guard let id = bookmark.podcastId else { return false }
        return playableEpisodeIds.contains(id)
    }
}
