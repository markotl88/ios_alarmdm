//
//  PlaybackState.swift
//  AlarmDM
//
//  What was playing, and where. Written when playback pauses or the app goes
//  away, read once at launch.
//

import Foundation

struct PlaybackState: Equatable {
    let podcastId: UUID
    let position: TimeInterval
    /// When it was written. Needed since the episode's own record started
    /// syncing: this slot is only ever the more recent of the two on the
    /// device that wrote it, and a position listened to on another device
    /// afterwards is newer than anything this one has to say.
    let savedAt: Date

    init(podcastId: UUID, position: TimeInterval, savedAt: Date = Date()) {
        self.podcastId = podcastId
        self.position = position
        self.savedAt = savedAt
    }
}

final class PlaybackStateStore {

    static let shared = PlaybackStateStore()

    private enum Key {
        static let podcastId = "lastPlayedPodcastId"
        static let position = "lastPlayedPosition"
        static let savedAt = "lastPlayedSavedAt"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var saved: PlaybackState? {
        guard let raw = defaults.string(forKey: Key.podcastId),
              let id = UUID(uuidString: raw) else { return nil }

        // A slot written before this app knew about dates is treated as very
        // old, so anything that has since synced wins over it.
        let savedAt = defaults.object(forKey: Key.savedAt) as? Date ?? .distantPast

        return PlaybackState(
            podcastId: id,
            position: defaults.double(forKey: Key.position),
            savedAt: savedAt
        )
    }

    /// Live radio is deliberately not saved. A position in a stream means
    /// nothing an hour later, and restoring the radio paused at a moment that
    /// has already gone out would be a lie about what the player is holding.
    func save(_ state: PlaybackState) {
        defaults.set(state.podcastId.uuidString, forKey: Key.podcastId)
        defaults.set(state.position, forKey: Key.position)
        defaults.set(state.savedAt, forKey: Key.savedAt)
    }

    func clear() {
        defaults.removeObject(forKey: Key.podcastId)
        defaults.removeObject(forKey: Key.position)
        defaults.removeObject(forKey: Key.savedAt)
    }
}
