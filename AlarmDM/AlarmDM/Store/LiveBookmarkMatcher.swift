//
//  LiveBookmarkMatcher.swift
//  AlarmDM
//
//  Puts a bookmark caught on live radio into the episode it belongs to, once
//  that episode is published.
//

import Foundation

enum LiveBookmarkMatcher {

    /// Finds the episode a live capture fell inside, and where in it.
    ///
    /// The episode carries `airedAt` — when the broadcast started — worked out
    /// by the backend from the publish time and the running time. Subtracting
    /// it from the moment the button was pressed gives the position directly.
    /// No schedule is involved, which is the point: the show has run 07–10 and
    /// 08–10 in different seasons, starts late often enough, and some days does
    /// not run at all.
    ///
    /// Returns nil rather than a guess. A live bookmark that finds no home
    /// stays as it is, and nothing is lost.
    static func match(_ bookmark: Bookmark, against episodes: [Podcast]) -> (episode: Podcast, position: TimeInterval)? {
        guard bookmark.isLive else { return nil }

        // Newest broadcast first, so a bookmark that could sit inside two
        // overlapping recordings lands in the later one.
        let candidates = episodes
            .filter { $0.isWithMusic && $0.airedAt != nil }
            .sorted { ($0.airedAt ?? .distantPast) > ($1.airedAt ?? .distantPast) }

        for episode in candidates {
            guard let airedAt = episode.airedAt else { continue }

            let position = bookmark.createdAt.timeIntervalSince(airedAt)
            guard position >= 0 else { continue }

            // The running time is the only check worth making: a bookmark that
            // falls past the end of the recording was caught during something
            // else, whatever the clock says.
            let duration = episode.durationInSeconds
            guard duration > 0, position <= duration else { continue }

            return (episode, position)
        }

        return nil
    }
}
