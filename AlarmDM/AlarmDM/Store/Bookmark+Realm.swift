//
//  Bookmark+Realm.swift
//  AlarmDM
//
//  Created by Marko Stajic on 22.10.2024.
//

import Foundation
import RealmSwift

class BookmarkRealm: Object {
    @Persisted(primaryKey: true) var id: Int
    @Persisted var title: String = ""
    @Persisted var note: String = ""
    @Persisted var createdAt: Date = Date()
    @Persisted var position: Double = 0.0
    @Persisted var category: String?

    @Persisted(originProperty: "bookmarks") var parentPodcast: LinkingObjects<PodcastRealm>
}

extension BookmarkRealm {
    convenience init(from bookmark: Bookmark, parentPodcast: PodcastRealm) {
        self.init()
        self.id = bookmark.id
        self.title = bookmark.title
        self.note = bookmark.note
        self.createdAt = bookmark.createdAt
        self.position = bookmark.position
        self.category = bookmark.category.rawValue
        parentPodcast.bookmarks.append(self)
    }
}
