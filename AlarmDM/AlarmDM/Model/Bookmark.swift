//
//  Bookmark.swift
//  AlarmDM
//
//  Created by Marko Stajic on 22.10.2024.
//

import Foundation

enum BookmarkCategory: String {
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

struct Bookmark: Identifiable, Equatable {
    var id: Int
    var title: String
    var note: String
    var createdAt: Date
    var duration: Double
    var category: BookmarkCategory
    var podcast: Podcast?
}

extension Bookmark {
    init(from bookmarkRealm: BookmarkRealm) {
        self.id = bookmarkRealm.id
        self.title = bookmarkRealm.title
        self.note = bookmarkRealm.note
        self.createdAt = bookmarkRealm.createdAt
        self.duration = bookmarkRealm.duration
        self.category = BookmarkCategory(rawValue: bookmarkRealm.category.rawValue) ?? .custom
        if let podcastRealm = bookmarkRealm.parentPodcast.first {
            self.podcast = Podcast(from: podcastRealm)
        } else {
            self.podcast = nil
        }
    }
}
