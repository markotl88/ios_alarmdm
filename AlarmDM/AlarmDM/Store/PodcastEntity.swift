//
//  PodcastEntity.swift
//  AlarmDM
//
//  The SwiftData shape of an episode: what the feed said about it, and
//  nothing a person did with it. Those live in EpisodeStateEntity and
//  DownloadEntity, one of which syncs and one of which does not.
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
    /// unmeasured - Podcast.outro falls back to the show's own figure.
    var outroSeconds: Double = 0

    var isWithMusic: Bool = false

    // What a person did with this episode is deliberately not here. Favourites
    // and listening live in EpisodeStateEntity, the downloaded file in
    // DownloadEntity - those two are the halves that sync and that stay on the
    // device, and neither belongs to a row that is rebuilt from the feed.

    init(from podcast: Podcast) {
        id = podcast.id
        apply(podcast)
    }

    /// Copies what the API knows, which by now is everything this row holds.
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
    /// Rebuilt from up to three rows: the episode as the feed described it,
    /// what the person has done with it, and whether it is on this device.
    /// The last two are optional because most episodes have neither.
    init(from entity: PodcastEntity,
         state: EpisodeStateEntity? = nil,
         download: DownloadEntity? = nil) {
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
        self.outroSeconds = entity.outroSeconds > 0 ? entity.outroSeconds : nil
        self.isWithMusic = entity.isWithMusic

        self.playedPosition = state?.playedPosition ?? 0
        self.playedAt = state?.playedAt
        self.isPlayed = state?.isPlayed ?? false
        self.isFavorite = state?.isFavorite ?? false

        self.fileUrl = download?.fileName
    }
}
