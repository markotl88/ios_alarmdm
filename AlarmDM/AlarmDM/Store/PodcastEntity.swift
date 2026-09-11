//
//  PodcastEntity.swift
//  AlarmDM
//
//  The SwiftData shape of an episode. Realm is still the live database — this
//  exists so the schema compiles and the store is created, one step before
//  anything reads from it.
//

import Foundation
import SwiftData

@Model
final class PodcastEntity {

    // Deliberately not @Attribute(.unique). CloudKit refuses unique
    // constraints, and this database is meant to sync between a person's
    // devices later. Identity is safe without it: Podcast.id is derived from
    // the media URL (UUID.stable), so two devices independently arrive at the
    // same id for the same episode, and the repository upserts by fetching
    // first rather than trusting the store to reject a duplicate.
    var id: UUID = UUID()

    // Every property has a default and every relationship is optional, which
    // is what CloudKit requires of a synced schema. Cheap now, expensive to
    // retrofit later.
    var title: String = ""
    var subtitle: String = ""
    var createdAt: Date?
    var timestamp: String?
    var podcastUrl: String = ""
    var duration: String = ""
    var lengthInBytes: Double = 0
    var itunesDuration: String = ""
    var show: String = Show.ostalo.rawValue

    /// Stays on this device even once the rest syncs: the file is local.
    var fileUrl: String?
    var isFavorite: Bool = false
    var isWithMusic: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \BookmarkEntity.podcast)
    var bookmarks: [BookmarkEntity]? = []

    init(from podcast: Podcast) {
        id = podcast.id
        apply(podcast)
    }

    /// Copies everything the API knows and leaves alone what only this device
    /// knows — the downloaded file and the favourite flag.
    func apply(_ podcast: Podcast) {
        title = podcast.title
        subtitle = podcast.subtitle
        createdAt = podcast.createdDate
        timestamp = podcast.timestamp
        podcastUrl = podcast.podcastUrl
        duration = podcast.duration
        lengthInBytes = podcast.lengthInBytes
        itunesDuration = podcast.itunesDuration
        show = podcast.show.rawValue
        isWithMusic = podcast.isWithMusic
    }
}

extension Podcast {
    init(from entity: PodcastEntity) {
        self.id = entity.id
        self.title = entity.title
        self.subtitle = entity.subtitle
        self.createdDate = entity.createdAt
        self.timestamp = entity.timestamp
        self.podcastUrl = entity.podcastUrl
        self.duration = entity.duration
        self.lengthInBytes = entity.lengthInBytes
        self.itunesDuration = entity.itunesDuration
        self.show = Show(rawValue: entity.show) ?? .ostalo
        self.fileUrl = entity.fileUrl
        self.isFavorite = entity.isFavorite
        self.isWithMusic = entity.isWithMusic
    }
}
