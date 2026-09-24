//
//  BookmarkLibrary.swift
//  AlarmDM
//
//  Capturing a bookmark, from wherever the button was pressed - the phone,
//  CarPlay, or the lock screen. One place, so the three cannot disagree.
//

import Foundation
import Combine

/// Where the button was pressed. The difference matters for what happens
/// next, not for what gets saved.
enum BookmarkOrigin {
    case phone
    case car
}

final class BookmarkLibrary {

    static let shared = BookmarkLibrary()

    /// Fires whenever the list changes, the same way EpisodeLibrary does, so a
    /// screen holding a snapshot knows to read again.
    let didChange = PassthroughSubject<Void, Never>()

    /// Fires when a bookmark was just captured, for whatever wants to
    /// acknowledge it - a flash on the button, a line in CarPlay.
    let didCapture = PassthroughSubject<(bookmark: Bookmark, origin: BookmarkOrigin), Never>()

    /// You press the button after the thing has happened, never before - but
    /// only just after, since the reaction is what makes you reach for it.
    /// Five seconds lands on the thing itself; fifteen lands on whatever came
    /// before it.
    static let rewind: TimeInterval = 5

    private let repository: BookmarkRepository
    private let podcasts: PodcastRepository
    private let engine: PlaybackEngine

    private var cancellables = Set<AnyCancellable>()

    init(repository: BookmarkRepository = .shared,
         podcasts: PodcastRepository = .shared,
         engine: PlaybackEngine = .shared,
         database: AppDatabase = .shared) {
        self.repository = repository
        self.podcasts = podcasts
        self.engine = engine

        // Bookmarks are the half of the database that syncs, so this is the
        // one list that can change without anyone touching this device.
        database.didChangeRemotely
            .sink { [weak self] in self?.didChange.send() }
            .store(in: &cancellables)
    }

    /// Saves immediately and asks nothing. The category can be added later from
    /// the list, which is the only shape that also works while driving.
    ///
    /// `showing` is what the screen has, for the press that arrives before the
    /// engine holds anything. The player can be open on an episode that was
    /// never opened - restoring at launch loads nothing into the engine on
    /// purpose, and the first press of play is what opens the audio - and
    /// reading only the engine meant the bookmark button sat there doing
    /// nothing at all until something had played. What the caller is looking
    /// at wins, because the caller is the one looking at it.
    @discardableResult
    func capture(categoryId: String? = nil,
                 origin: BookmarkOrigin = .phone,
                 showing episode: Podcast? = nil,
                 at position: TimeInterval = 0) -> Bookmark? {

        let bookmark: Bookmark

        if let episode {
            bookmark = Bookmark(
                id: UUID(),
                createdAt: Date(),
                position: max(0, position - Self.rewind),
                categoryId: categoryId,
                note: "",
                episodeTitle: episode.title,
                show: episode.show,
                podcastId: episode.id,
                capturedLive: false
            )
            return save(bookmark, origin: origin)
        }

        guard let source = engine.source else { return nil }

        switch source {
        case .podcast(let podcast):
            bookmark = Bookmark(
                id: UUID(),
                createdAt: Date(),
                position: max(0, engine.currentTime - Self.rewind),
                categoryId: categoryId,
                note: "",
                episodeTitle: podcast.title,
                show: podcast.show,
                podcastId: podcast.id,
                capturedLive: false
            )

        case .radio:
            // Live radio has no position to point at, so the moment it was
            // caught is the only handle - along with whatever the station
            // happened to be announcing. If it announced a song, the category
            // is not a guess: that is what was playing.
            let announced = engine.liveTrack != nil
            bookmark = Bookmark(
                id: UUID(),
                createdAt: Date(),
                position: 0,
                categoryId: categoryId ?? (announced ? BookmarkCategory.muzika.rawValue : nil),
                note: engine.liveTrack?.display ?? "",
                episodeTitle: "Radio uživo",
                show: nil,
                podcastId: nil,
                capturedLive: true
            )
        }

        return save(bookmark, origin: origin)
    }

    /// Writing one down, announcing it and counting it - the same three steps
    /// whichever way the bookmark was arrived at.
    @discardableResult
    private func save(_ bookmark: Bookmark, origin: BookmarkOrigin) -> Bookmark {
        repository.add(bookmark)
        didChange.send()
        Analytics.record(.bookmarkCreated, [
            "origin": origin == .car ? "car" : "phone",
            "kind": bookmark.capturedLive ? "live" : "episode",
        ])
        didCapture.send((bookmark: bookmark, origin: origin))
        return bookmark
    }

    func all() -> [Bookmark] { repository.all() }

    /// Tries to put every live capture into the episode it fell inside, now
    /// that episodes have arrived. Cheap enough to run whenever the list is
    /// looked at: it does nothing at all unless a live bookmark is waiting.
    @discardableResult
    func reconcileLiveCaptures() -> Int {
        let captures = repository.all().filter { $0.capturedLive || $0.podcastId != nil }
        guard !captures.isEmpty else { return 0 }

        let episodes = podcasts.broadcastEpisodes()
        guard !episodes.isEmpty else { return 0 }

        var changed = 0
        for bookmark in captures {
            if bookmark.isAwaitingEpisode {
                guard let hit = LiveBookmarkMatcher.match(bookmark, against: episodes) else { continue }
                repository.link(bookmark.id, to: hit.episode, position: hit.position)
                changed += 1
            } else if let moved = correctedPosition(for: bookmark, in: episodes) {
                repository.setPosition(moved, for: bookmark.id)
                changed += 1
            }
        }

        if changed > 0 { didChange.send() }
        return changed
    }

    /// A placed live capture, worked out again against the episode's current
    /// broadcast time. Returns nil when nothing moved.
    ///
    /// The window is what makes this safe for bookmarks made before the app
    /// recorded how they were captured. A bookmark taken while listening to a
    /// recording would come out hours away from where it sits, so anything
    /// that far off is left alone; only a small correction is ever applied,
    /// which is all a corrected broadcast time can produce.
    private func correctedPosition(for bookmark: Bookmark, in episodes: [Podcast]) -> TimeInterval? {
        guard let podcastId = bookmark.podcastId,
              let episode = episodes.first(where: { $0.id == podcastId }),
              let position = LiveBookmarkMatcher.position(of: bookmark, in: episode) else { return nil }

        let moved = position - bookmark.position
        guard abs(moved) > 1 else { return nil }
        guard bookmark.capturedLive || abs(moved) < 15 * 60 else { return nil }

        return position
    }

    func setCategory(_ categoryId: String?, for id: UUID) {
        repository.setCategory(categoryId, for: id)
        didChange.send()
    }

    func setNote(_ note: String, for id: UUID) {
        repository.setNote(note, for: id)
        didChange.send()
    }

    func deleteAll() {
        repository.deleteAll()
        didChange.send()
    }

    func delete(_ id: UUID) {
        repository.delete(id)
        didChange.send()
    }
}
