//
//  ListeningRecorder.swift
//  AlarmDM
//
//  The one place that writes down how far a listen got. It watches the
//  engine, not a screen, so a listen is written down wherever it happened.
//

import Foundation
import Combine
import UIKit

/// Writes down where an episode got to: when playback stops, when the engine
/// moves on to something else, when the app goes away, and once a minute
/// while it plays.
///
/// This used to be the player screen's job, and the player screen does not
/// always exist. When the car starts the app, iOS brings up the CarPlay scene
/// and nothing else - no phone window, no view model - and every listen in
/// the car went unrecorded. Pulling the cable paused the audio correctly and
/// nobody wrote the pause down, so the next start went back to wherever the
/// phone had last been paused by hand. The engine exists whichever way the
/// app was started, and so does this.
///
/// Only what the engine has actually played is ever written. An episode
/// merely shown in the player - restored at launch, or followed from another
/// device - has not been listened to here, and writing it down would date it
/// now and send the other device chasing it.
final class ListeningRecorder {

    static let shared = ListeningRecorder()

    /// While playing, a write at least this often. Pausing and leaving are
    /// caught as they happen; this is for what is not - the app ended by the
    /// system mid-listen, or a crash, which otherwise lose the whole listen.
    static let interval: TimeInterval = 60

    private let engine: PlaybackEngineType
    private let progressStore: ProgressRecording
    private let playbackState: PlaybackStateStore
    private let notifications: NotificationCenter
    private var cancellables = Set<AnyCancellable>()

    /// The episode the engine holds, if it holds one.
    private var episode: Podcast?
    /// The last real position heard for it. Never zero: the engine reports
    /// zero while a new item opens, and that is not where anybody got to.
    private var position: TimeInterval?
    /// Where the last minute was counted from.
    private var minuteMark: TimeInterval?
    /// Where the last write for this episode was.
    private var lastWritten: TimeInterval?
    private var isPlaying = false
    /// Raised when the position was moved by another device and nobody here
    /// has listened since. While it is up, nothing is written: what would be
    /// written is somebody else's listening with this device's name and this
    /// moment's date on it.
    private var isAdopted = false

    init(engine: PlaybackEngineType = PlaybackEngine.shared,
         progressStore: ProgressRecording = EpisodeLibrary.shared,
         playbackState: PlaybackStateStore = .shared,
         notifications: NotificationCenter = .default) {
        self.engine = engine
        self.progressStore = progressStore
        self.playbackState = playbackState
        self.notifications = notifications
    }

    /// From the app delegate, which runs however the app was started.
    ///
    /// Subscribed without hopping queues on purpose. The engine publishes on
    /// the main thread already, and a write has to land before whatever the
    /// caller does next - closing the player writes down the stop and then
    /// clears what to reopen, and a write delivered a runloop later would
    /// undo the clearing.
    func start() {
        guard cancellables.isEmpty else { return }

        // The engine announces the new source before it resets the clock, so
        // at this moment `position` still belongs to the episode being left.
        engine.sourcePublisher
            .sink { [weak self] in self?.sourceChanged(to: $0) }
            .store(in: &cancellables)

        engine.currentTimePublisher
            .sink { [weak self] in self?.timeChanged(to: $0) }
            .store(in: &cancellables)

        engine.isPlayingPublisher
            .sink { [weak self] playing in
                guard let self else { return }
                let wasPlaying = self.isPlaying
                self.isPlaying = playing
                // Playing here is what makes the position this device's own
                // again, whoever set it.
                if playing { self.isAdopted = false }
                if wasPlaying && !playing { self.write("paused") }
            }
            .store(in: &cancellables)

        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
            notifications.publisher(for: name)
                .sink { [weak self] _ in self?.write("leaving") }
                .store(in: &cancellables)
        }
    }

    private func sourceChanged(to source: PlaybackSource?) {
        let next: Podcast?
        if case .podcast(let podcast) = source { next = podcast } else { next = nil }

        // The same episode handed over again - rebuilt after an interruption,
        // or a refreshed copy - is not a change of episode.
        if let next, next.id == episode?.id {
            episode = next
            return
        }

        write("left")
        episode = next
        position = nil
        minuteMark = nil
        lastWritten = nil
        isAdopted = false
    }

    /// A position that arrived from another device, not from anybody here.
    ///
    /// The player moves the engine to it while paused, so that pressing play
    /// carries on from where the other device got to. Without this the move
    /// looks exactly like listening: the next write - going to the background,
    /// say - would stamp that position with this moment and hand this device
    /// the account's newest listen, over the device that actually listened.
    ///
    /// Recorded as already written, so nothing is written until somebody here
    /// listens past it. A move made by hand, by dragging the scrubber, is not
    /// this and still counts.
    func noteAdopted(position: TimeInterval) {
        guard position > 0 else { return }
        self.position = position
        lastWritten = position
        minuteMark = position
        isAdopted = true
    }

    /// Somebody here dragged the scrubber. That is this device listening -
    /// or at least deciding - so whatever was adopted is now this device's
    /// own position, and writing resumes.
    func noteMovedByHand(to position: TimeInterval) {
        guard position > 0 else { return }
        self.position = position
        minuteMark = position
        isAdopted = false
    }

    private func timeChanged(to time: TimeInterval) {
        guard episode != nil, time.isFinite, time > 0 else { return }
        position = time

        guard let minuteMark else {
            // The first real position is where this stretch of listening
            // starts; a minute is counted from there.
            self.minuteMark = time
            return
        }
        if isPlaying, abs(time - minuteMark) >= ListeningRecorder.interval {
            write("minute")
        }
    }

    private func write(_ reason: String) {
        guard let episode, let position, position > 0 else { return }

        // Moved by another device and not listened to here since. The seek
        // lands within a second of what was asked for, or does not land at
        // all, and either way the number that comes back is not a listen -
        // which is why this is a flag and not a comparison of seconds.
        guard !isAdopted else { return }

        // Nothing moved since the last write - paused, and then the app went
        // to the background, or the player was closed. Writing again would
        // only change the date, and the date is what decides which device
        // listened last: a phone paused at 58 minutes and put away an hour
        // later would claim the account's newest listen over the Mac that
        // finished the episode in between.
        if let lastWritten, abs(position - lastWritten) < 1 {
            minuteMark = position
            return
        }

        let end = episode.endOfShow
        progressStore.recordProgress(position: position, hasFinished: end > 0 && position >= end, for: episode.id)
        playbackState.save(PlaybackState(podcastId: episode.id, position: position))
        lastWritten = position
        minuteMark = position

        #if DEBUG
        AppLog.write(.player, "recorded \(Int(position))s (\(reason)) - \(episode.title)")
        #endif
    }
}
