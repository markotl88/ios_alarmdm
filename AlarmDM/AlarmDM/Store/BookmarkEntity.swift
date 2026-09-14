//
//  BookmarkEntity.swift
//  AlarmDM
//

import Foundation
import SwiftData

@Model
final class BookmarkEntity {

    /// A UUID, unlike BookmarkRealm's Int. Two devices have to be able to
    /// create a bookmark at the same moment without colliding, and an
    /// incrementing integer cannot promise that.
    var id: UUID = UUID()

    var createdAt: Date = Date()

    /// Seconds into the episode; zero for a live capture.
    var position: Double = 0

    /// The raw value of BookmarkCategory, stored as a string so a category
    /// added later does not make an older row unreadable.
    var category: String?
    var note: String = ""

    /// Copied at capture rather than read through the relationship. An episode
    /// row can fall out of the cache, and a bookmark that cannot say what it
    /// belongs to is worthless.
    var episodeTitle: String = ""
    var show: String?

    /// The episode it belongs to, nil for a live capture that has not found
    /// one yet. An id rather than a relationship: bookmarks sync and the
    /// episode cache does not, and a relationship cannot reach across two
    /// stores. Nothing is lost by it — the title and show are copied here
    /// anyway, precisely so a bookmark survives an episode row it cannot see.
    var podcastId: UUID?

    /// Caught on live radio. Kept after the episode is found, so a corrected
    /// broadcast time can move it again.
    var capturedLive: Bool = false

    init(from bookmark: Bookmark, podcastId: UUID? = nil) {
        id = bookmark.id
        createdAt = bookmark.createdAt
        position = bookmark.position
        category = bookmark.category?.rawValue
        note = bookmark.note
        episodeTitle = bookmark.episodeTitle
        show = bookmark.show?.rawValue
        capturedLive = bookmark.capturedLive
        self.podcastId = podcastId
    }
}

extension Bookmark {
    init(from entity: BookmarkEntity) {
        self.id = entity.id
        self.createdAt = entity.createdAt
        self.position = entity.position
        self.category = entity.category.flatMap(BookmarkCategory.init(rawValue:))
        self.note = entity.note
        self.episodeTitle = entity.episodeTitle
        self.show = entity.show.flatMap(Show.init(rawValue:))
        self.podcastId = entity.podcastId
        self.capturedLive = entity.capturedLive
    }
}
