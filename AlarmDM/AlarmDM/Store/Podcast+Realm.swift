//
//  Podcast+Realm.swift
//  AlarmDM
//
//  Created by Marko Stajic on 22.10.2024.
//

import Foundation
import Realm
import RealmSwift

class PodcastRealm: Object {
    @Persisted(primaryKey: true) var id: String
    @Persisted var title: String = ""
    @Persisted var subtitle: String = ""
    @Persisted var createdAt: Date?
    @Persisted var timestamp: String?
    @Persisted var podcastUrl: String = ""
    @Persisted var duration: String = ""
    @Persisted var lengthInBytes: Double = 0.0
    @Persisted var itunesDuration: String = ""

    @Persisted var show: String?
    @Persisted var fileUrl: String?
    @Persisted var isFavorite: Bool = false
    @Persisted var isWithMusic: Bool = false

    @Persisted var bookmarks = List<BookmarkRealm>()
}
