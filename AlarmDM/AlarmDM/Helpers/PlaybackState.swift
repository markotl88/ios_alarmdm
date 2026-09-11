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
}

final class PlaybackStateStore {

    static let shared = PlaybackStateStore()

    private enum Key {
        static let podcastId = "lastPlayedPodcastId"
        static let position = "lastPlayedPosition"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var saved: PlaybackState? {
        guard let raw = defaults.string(forKey: Key.podcastId),
              let id = UUID(uuidString: raw) else { return nil }
        return PlaybackState(podcastId: id, position: defaults.double(forKey: Key.position))
    }

    /// Live radio is deliberately not saved. A position in a stream means
    /// nothing an hour later, and restoring the radio paused at a moment that
    /// has already gone out would be a lie about what the player is holding.
    func save(_ state: PlaybackState) {
        defaults.set(state.podcastId.uuidString, forKey: Key.podcastId)
        defaults.set(state.position, forKey: Key.position)
    }

    func clear() {
        defaults.removeObject(forKey: Key.podcastId)
        defaults.removeObject(forKey: Key.position)
    }
}
