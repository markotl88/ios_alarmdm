//
//  Bookmark+Realm.swift
//  AlarmDM
//
//  Created by Marko Stajic on 22.10.2024.
//

import Foundation
import RealmSwift

enum BookmarkCategoryRealm: String, PersistableEnum {
    case film
    case muzika
    case serija
    case knjiga
    case zoli
    case krvarenjeIzUsiju
    case daskoMasti
    case daskoRant
    case mladjaDobarCovek
    case custom
}

class BookmarkRealm: Object {
    @Persisted(primaryKey: true) var id: Int
    @Persisted var title: String = ""
    @Persisted var note: String = ""
    @Persisted var createdAt: Date = Date()
    @Persisted var duration: Double = 0.0
    @Persisted var category: BookmarkCategoryRealm = .custom

    @Persisted(originProperty: "bookmarks") var parentPodcast: LinkingObjects<PodcastRealm>
}

extension BookmarkRealm {
    convenience init(from bookmark: Bookmark, parentPodcast: PodcastRealm) {
        self.init()
        self.id = bookmark.id
        self.title = bookmark.title
        self.note = bookmark.note
        self.createdAt = bookmark.createdAt
        self.duration = bookmark.duration
        self.category = BookmarkCategoryRealm(rawValue: bookmark.category.rawValue) ?? .custom
        parentPodcast.bookmarks.append(self)
    }
}
