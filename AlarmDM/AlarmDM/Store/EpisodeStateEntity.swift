//
//  EpisodeStateEntity.swift
//  AlarmDM
//
//  What a person has done with an episode, as opposed to what the episode is.
//  This is the half that syncs.
//

import Foundation
import SwiftData

/// Favouriting and listening, kept apart from the episode itself.
///
/// The episode rows are a cache of the feed: five thousand of them, rebuilt
/// from the API whenever it answers, and identical on every device that asks.
/// Carrying them through iCloud would spend a person's storage on something
/// they can have for free, and would sync a download path that means nothing
/// on the other device. What cannot be had for free is this: what they marked,
/// what they heard, and how far they got.
///
/// Keyed by `podcastId` rather than by a relationship, because a relationship
/// cannot cross two stores and the episodes live in the local one.
@Model
final class EpisodeStateEntity {

    /// The episode this is about. Not `@Attribute(.unique)` - CloudKit refuses
    /// unique constraints - so the repository fetches before it inserts.
    var podcastId: UUID = UUID()

    var isFavorite: Bool = false

    /// How far the last listen got, in seconds.
    var playedPosition: Double = 0

    /// When that position was written down, and the tiebreaker when two
    /// devices disagree: CloudKit keeps whichever write landed last, which is
    /// not the same as the listen that happened last.
    var playedAt: Date?

    /// Crossed the end of the show - see Podcast.endOfShow. Sticky: listening
    /// again from the start does not un-finish an episode.
    var isPlayed: Bool = false

    /// Enough to show a row on a device that has never cached this episode.
    /// Copied, not looked up, for the same reason a bookmark copies its title.
    var episodeTitle: String = ""
    var show: String?

    /// Which of two rows for the same episode describes the later listen.
    /// A row that has never been played has no date at all, and loses to one
    /// that has.
    static func isNewer(_ lhs: EpisodeStateEntity, than rhs: EpisodeStateEntity) -> Bool {
        (lhs.playedAt ?? .distantPast) > (rhs.playedAt ?? .distantPast)
    }

    /// What several rows for one episode add up to: the later listen's
    /// position, and flags from all of them.
    ///
    /// Both halves matter, and they used to disagree. A list took the newest
    /// row whole, an episode opened on its own OR-ed the flags, so an episode
    /// favourited on one device and listened to later on another was missing
    /// from the favourites list until the player had been opened on it. One
    /// rule now, read from both.
    ///
    /// A position is a moment and the later moment is the true one. A flag is
    /// a decision, and a decision made on either device stands - which is
    /// also why unfavouriting cannot yet travel: see the note on that in
    /// PodcastRepository.merged.
    static func effective(_ rows: [EpisodeStateEntity]) -> EpisodeState? {
        let sorted = rows.sorted { isNewer($0, than: $1) }
        guard let newest = sorted.first else { return nil }

        return EpisodeState(
            playedPosition: newest.playedPosition,
            playedAt: newest.playedAt,
            isPlayed: sorted.contains { $0.isPlayed },
            isFavorite: sorted.contains { $0.isFavorite }
        )
    }

    init(podcastId: UUID, title: String = "", show: String? = nil) {
        self.podcastId = podcastId
        self.episodeTitle = title
        self.show = show
    }
}

/// What the app reads: the rows folded into one answer, as values rather
/// than as stored objects, so reading never has to touch the store.
struct EpisodeState: Equatable {
    var playedPosition: Double = 0
    var playedAt: Date?
    var isPlayed = false
    var isFavorite = false
}
