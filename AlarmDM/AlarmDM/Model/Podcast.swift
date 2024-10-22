//
//  Podcast.swift
//  AlarmDM
//
//  Created by Marko Stajic on 22.10.2024.
//

import Foundation

enum Show: String {
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

struct Podcast: Identifiable, Equatable {
    var id: UUID = UUID()
    var title = ""
    var subtitle = ""
    var createdDate: Date?
    var timestamp: String?
    var podcastUrl = ""
    var duration = ""
    var lengthInBytes = 0.0
    var itunesDuration = ""
    
    var show: Show?
    var fileUrl: String?
    var isFavorite = false
    var isWithMusic = false
    var isDownloaded: Bool {
        fileUrl != nil
    }
    var bookmarks: [Bookmark]?
    
//    init(from podcastResponse: PodcastResponse) {
//        id = podcastResponse.id
//        title = podcastResponse.title
//        subtitle = podcastResponse.subtitle
//        timestamp = podcastResponse.timestamp
//        podcastUrl = podcastResponse.podcastUrl
//        duration = podcastResponse.duration
//        lengthInBytes = podcastResponse.lengthInBytes
//        itunesDuration = podcastResponse.itunesDuration
//        createdDate = podcastResponse.createdDate.formattedCreatedDate
//    }
}

extension Podcast {
    init(from podcastRealm: PodcastRealm) {
        self.id = UUID(uuidString: podcastRealm.id) ?? UUID() // Convert String to UUID, fallback to a new UUID if conversion fails
        self.title = podcastRealm.title
        self.subtitle = podcastRealm.subtitle
        self.createdDate = podcastRealm.createdAt
        self.timestamp = podcastRealm.timestamp
        self.podcastUrl = podcastRealm.podcastUrl
        self.duration = podcastRealm.duration
        self.lengthInBytes = podcastRealm.lengthInBytes
        self.itunesDuration = podcastRealm.itunesDuration
        self.show = Show(rawValue: podcastRealm.type?.rawValue ?? "")
        self.fileUrl = podcastRealm.fileUrl
        self.isFavorite = podcastRealm.isFavorite
        self.isWithMusic = podcastRealm.isWithMusic
    }
}
