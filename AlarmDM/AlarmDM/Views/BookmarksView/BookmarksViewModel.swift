//
//  BookmarksViewModel.swift
//  AlarmDM
//

import Foundation
import Combine

final class BookmarksViewModel: ObservableObject {

    @Published private(set) var bookmarks: [Bookmark] = []
    /// nil means every category, including the ones with none set.
    @Published var activeCategory: BookmarkCategory?

    private let library: BookmarkLibrary
    private let podcasts: PodcastRepository
    private var cancellables = Set<AnyCancellable>()

    init(library: BookmarkLibrary = .shared, podcasts: PodcastRepository = .shared) {
        self.library = library
        self.podcasts = podcasts
        reload()

        library.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reload() }
            .store(in: &cancellables)
    }

    func reload() {
        bookmarks = library.all()
    }

    var visibleBookmarks: [Bookmark] {
        guard let activeCategory else { return bookmarks }
        return bookmarks.filter { $0.category == activeCategory }
    }

    /// Only offer the categories that are actually in use — a filter that can
    /// only ever return nothing is a dead end.
    var availableCategories: [BookmarkCategory] {
        let used = Set(bookmarks.compactMap(\.category))
        return BookmarkCategory.allCases.filter { used.contains($0) }
    }

    var isEmpty: Bool { bookmarks.isEmpty }

    // MARK: - Actions

    func setCategory(_ category: BookmarkCategory?, for bookmark: Bookmark) {
        library.setCategory(category, for: bookmark.id)
    }

    func delete(_ bookmark: Bookmark) {
        library.delete(bookmark.id)
        if activeCategory != nil && visibleBookmarks.isEmpty { activeCategory = nil }
    }

    /// The episode behind a bookmark, when the store still holds it. A live
    /// capture never has one, and a cached row can have been replaced.
    func episode(for bookmark: Bookmark) -> Podcast? {
        guard let podcastId = bookmark.podcastId else { return nil }
        return podcasts.podcast(with: podcastId)
    }
}
