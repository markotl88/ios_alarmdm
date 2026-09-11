//
//  BookmarkEntity.swift
//  AlarmDM
//
//  A moment in an episode worth coming back to.
//

import Foundation
import SwiftData

@Model
final class BookmarkEntity {

    /// A UUID, unlike BookmarkRealm's Int. Two devices must be able to create
    /// bookmarks at the same time without colliding, and an incrementing
    /// integer cannot promise that.
    var id: UUID = UUID()

    var title: String = ""
    var note: String = ""
    var createdAt: Date = Date()

    /// Where in the episode it points, in seconds.
    var position: Double = 0

    /// The raw value of BookmarkCategory. Stored as a string so a category
    /// added in a later version does not make an old row unreadable.
    var category: String?

    var podcast: PodcastEntity?

    init(position: Double,
         category: String? = nil,
         title: String = "",
         note: String = "",
         podcast: PodcastEntity? = nil) {
        self.position = position
        self.category = category
        self.title = title
        self.note = note
        self.podcast = podcast
    }
}
