//
//  BookmarkLibrary.swift
//  AlarmDM
//
//  Capturing a bookmark, from wherever the button was pressed — the phone,
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
    /// acknowledge it — a flash on the button, a line in CarPlay.
    let didCapture = PassthroughSubject<(bookmark: Bookmark, origin: BookmarkOrigin), Never>()

    /// You press the button after the thing has happened, never before — but
    /// only just after, since the reaction is what makes you reach for it.
    /// Five seconds lands on the thing itself; fifteen lands on whatever came
    /// before it.
    static let rewind: TimeInterval = 5

    private let repository: BookmarkRepository
    private let engine: PlaybackEngine

    init(repository: BookmarkRepository = .shared, engine: PlaybackEngine = .shared) {
        self.repository = repository
        self.engine = engine
    }

    var canCapture: Bool { engine.source != nil }

    /// Saves immediately and asks nothing. The category can be added later from
    /// the list, which is the only shape that also works while driving.
    @discardableResult
    func capture(category: BookmarkCategory? = nil, origin: BookmarkOrigin = .phone) -> Bookmark? {
        guard let source = engine.source else { return nil }

        let bookmark: Bookmark
        switch source {
        case .podcast(let podcast):
            bookmark = Bookmark(
                id: UUID(),
                createdAt: Date(),
                position: max(0, engine.currentTime - Self.rewind),
                category: category,
                note: "",
                episodeTitle: podcast.title,
                show: podcast.show,
                podcastId: podcast.id
            )

        case .radio:
            // Live radio has no position to point at, so the moment it was
            // caught is the only handle — along with whatever the station
            // happened to be announcing.
            bookmark = Bookmark(
                id: UUID(),
                createdAt: Date(),
                position: 0,
                category: category,
                note: engine.liveTrack?.display ?? "",
                episodeTitle: "Radio uživo",
                show: nil,
                podcastId: nil
            )
        }

        repository.add(bookmark)
        didChange.send()
        didCapture.send((bookmark: bookmark, origin: origin))
        return bookmark
    }

    func all() -> [Bookmark] { repository.all() }

    func setCategory(_ category: BookmarkCategory?, for id: UUID) {
        repository.setCategory(category, for: id)
        didChange.send()
    }

    func setNote(_ note: String, for id: UUID) {
        repository.setNote(note, for: id)
        didChange.send()
    }

    func delete(_ id: UUID) {
        repository.delete(id)
        didChange.send()
    }
}
