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
    /// When it went out live, for matching a live bookmark to its place in the
    /// recording. Only the full cut has one.
    var airedAt: Date?
    var timestamp: String?
    var podcastUrl: String = ""
    var duration: String = ""
    var lengthInBytes: Double = 0
    var itunesDuration: String = ""
    var show: String = Show.ostalo.rawValue
    /// The closing credits, in seconds, as the backend measured them. Zero is
    /// unmeasured — Podcast.outro falls back to the show's own figure.
    var outroSeconds: Double = 0

    /// How far the last listen got, in seconds.
    var playedPosition: Double = 0

    /// When that position was written down. This is the tiebreaker once the
    /// store syncs: CloudKit resolves nothing on its own, it keeps whichever
    /// write landed last — and the write that landed last is not the listen
    /// that happened last. Comparing this instead means the phone that
    /// listened yesterday cannot overwrite the iPad that listened this
    /// morning.
    var playedAt: Date?

    /// Crossed the end of the show — the running time minus the closing
    /// credits, see Podcast.endOfShow. Sticky: listening again from the start
    /// does not un-finish an episode.
    var isPlayed: Bool = false

    /// Stays on this device even once the rest syncs: the file is local.
    var fileUrl: String?
    var isFavorite: Bool = false
    var isWithMusic: Bool = false

    /// Nullify, not cascade: a bookmark is something a person made, and it
    /// should not disappear because the cached episode row did.
    @Relationship(deleteRule: .nullify, inverse: \BookmarkEntity.podcast)
    var bookmarks: [BookmarkEntity]? = []

    init(from podcast: Podcast) {
        id = podcast.id
        apply(podcast)
    }

    /// Copies everything the API knows and leaves alone what only this device
    /// knows — the downloaded file, the favourite flag, and how far this
    /// episode has been listened to.
    func apply(_ podcast: Podcast) {
        title = podcast.title
        subtitle = podcast.subtitle
        createdAt = podcast.createdDate
        airedAt = podcast.airedAt
        timestamp = podcast.timestamp
        podcastUrl = podcast.podcastUrl
        duration = podcast.duration
        lengthInBytes = podcast.lengthInBytes
        itunesDuration = podcast.itunesDuration
        show = podcast.show.rawValue
        outroSeconds = podcast.outroSeconds ?? 0
        isWithMusic = podcast.isWithMusic
    }
}

extension Podcast {
    init(from entity: PodcastEntity) {
        self.id = entity.id
        self.title = entity.title
        self.subtitle = entity.subtitle
        self.createdDate = entity.createdAt
        self.airedAt = entity.airedAt
        self.timestamp = entity.timestamp
        self.podcastUrl = entity.podcastUrl
        self.duration = entity.duration
        self.lengthInBytes = entity.lengthInBytes
        self.itunesDuration = entity.itunesDuration
        self.show = Show(rawValue: entity.show) ?? .ostalo
        self.playedPosition = entity.playedPosition
        self.playedAt = entity.playedAt
        self.isPlayed = entity.isPlayed
        self.outroSeconds = entity.outroSeconds > 0 ? entity.outroSeconds : nil
        self.fileUrl = entity.fileUrl
        self.isFavorite = entity.isFavorite
        self.isWithMusic = entity.isWithMusic
    }
}
