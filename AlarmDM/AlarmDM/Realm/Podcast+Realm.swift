//
//  Podcast+Realm.swift
//  AlarmDM
//
//  Created by Marko Stajic on 22.10.2024.
//

import Foundation
import Realm
import RealmSwift

enum ShowRealm: String, PersistableEnum {
    case alarmSaDaskomIMladjom
    case ljudiIzPodzemlja
    case naIviciOfsajda
    case topleLjuckePrice
    case mozemoSamoDaSeSlikamo
    case punaUstaPoezije
    case rastrojavanje
    case vecernjaSkolaRokenrola
    case sportskiPozdrav
    case unutrasnjaEmigracija
}

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

    @Persisted var type: ShowRealm?
    @Persisted var fileUrl: String?
    @Persisted var isFavorite: Bool = false
    @Persisted var isWithMusic: Bool = false

    @Persisted var bookmarks = List<BookmarkRealm>()
}

extension PodcastRealm {
    convenience init(from podcast: Podcast) {
        self.init()
        self.id = podcast.id.uuidString // Convert to Int, but provide fallback in case the string can't convert
        self.title = podcast.title
        self.subtitle = podcast.subtitle
        self.createdAt = podcast.createdDate
        self.timestamp = podcast.timestamp
        self.podcastUrl = podcast.podcastUrl
        self.duration = podcast.duration
        self.lengthInBytes = podcast.lengthInBytes
        self.itunesDuration = podcast.itunesDuration
        self.type = ShowRealm(rawValue: podcast.show?.rawValue ?? "")
        self.fileUrl = podcast.fileUrl
        self.isFavorite = podcast.isFavorite
        self.isWithMusic = podcast.isWithMusic
        if let bookmarkList = podcast.bookmarks {
            for bookmark in bookmarkList {
                let bookmarkRealm = BookmarkRealm(from: bookmark, parentPodcast: self)
                self.bookmarks.append(bookmarkRealm)
            }
        }
    }
}

extension PodcastRealm {
    convenience init(from response: PodcastResponse) {
        self.init()
        self.id = response.id// Assuming PodcastResponse.id is a String; safely convert to Int
        self.title = response.title
        self.subtitle = response.subtitle
        self.timestamp = response.timestamp
        self.podcastUrl = response.podcastUrl
        self.duration = response.duration
        self.lengthInBytes = response.lengthInBytes
        self.itunesDuration = response.itunesDuration
        self.fileUrl = response.fileUrl
        
        // Convert createdDate from String to Date if applicable
        if let date = response.createdDate.formattedCreatedDate {
            self.createdAt = date
        }
    }
}
