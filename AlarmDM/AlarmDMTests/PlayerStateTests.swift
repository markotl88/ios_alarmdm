//
//  PlayerStateTests.swift
//  AlarmDMTests
//
//  What the player does when what it is playing changes: which position is
//  picked up, which one wins when two of them disagree, and - in
//  ListeningRecorderTests - when a listen is written down at all. Driven by
//  a fake engine, so none of it needs AVFoundation, a file, or the network.
//

import XCTest
import Combine
import UIKit
import AVFoundation
@testable import AlarmDM

final class PlayerStateTests: XCTestCase {

    private var engine: FakePlaybackEngine!
    private var episodes: EpisodeStore!
    private var defaults: UserDefaults!
    /// Stands in for "something arrived from another device".
    private var storeChanges: PassthroughSubject<Void, Never>!
    private var progress: ProgressSpy!
    private var notifications: NotificationCenter!

    /// Three hours, so the credits settle where it ends: 3:00:00 minus twenty
    /// seconds is 10 780, comfortably past ninety-five percent.
    private var alarm: Podcast!
    /// A second episode, to switch to.
    private var second: Podcast!

    override func setUpWithError() throws {
        engine = FakePlaybackEngine()
        episodes = EpisodeStore()
        storeChanges = PassthroughSubject()
        progress = ProgressSpy()
        notifications = NotificationCenter()

        defaults = UserDefaults(suiteName: "PlayerStateTests")
        defaults.removePersistentDomain(forName: "PlayerStateTests")

        alarm = makeEpisode(title: "Alarm", show: .alarmSaDaskomIMladjom, duration: "3:00:00")
        second = makeEpisode(title: "Emigracija", show: .unutrasnjaEmigracija, duration: "2:00:00")
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: "PlayerStateTests")
    }

    // MARK: - Leaving one episode for another

    /// The same episode arriving again as a refreshed row - a favourite
    /// toggled, a download finished - is not a swap.
    func testReselectingTheSameEpisodeLeavesPlaybackAlone() {
        let player = makePlayer()

        player.mode = .podcast(podcast: alarm)
        player.togglePlayPause()
        flush()
        engine.advance(to: 600)
        flush()

        var refreshed = alarm!
        refreshed.isFavorite = true
        player.mode = .podcast(podcast: refreshed)

        XCTAssertEqual(player.currentTime, 600, accuracy: 1)
        XCTAssertEqual(engine.playCalls.count, 1)
    }

    /// Opening a stream takes a moment, and the scrubber used to spend it at
    /// zero: the engine reports nothing until the file is open, and the bar
    /// believed it. It shows where the episode is going instead, from what
    /// the feed already said about its length.
    func testTheScrubberDoesNotFallToTheStartWhileAStreamOpens() {
        var heard = alarm!
        heard.playedPosition = 3_600
        heard.playedAt = Date()
        episodes.rows[heard.id] = heard

        let player = makePlayer()
        player.mode = .podcast(podcast: heard)
        player.togglePlayPause()
        flush()

        // What an unopened file reports: no length at all.
        engine.reportDuration(0)
        flush()

        XCTAssertEqual(player.playbackProgress, 3_597 / 10_800, accuracy: 0.01)
    }

    /// The episode row is rewritten the moment playback pauses - that is when
    /// progress is written down - so by the time play is pressed again, the
    /// value the player holds no longer equals the one the engine was given.
    /// Deciding "is this already loaded" by comparing those values answers no,
    /// and the file starts again from the beginning.
    func testPausingAndPlayingAgainDoesNotStartTheEpisodeOver() {
        let player = makePlayer()

        player.mode = .podcast(podcast: alarm)
        player.togglePlayPause()
        flush()
        engine.advance(to: 600)
        flush()

        player.togglePlayPause()
        flush()

        // What happens for real when playback pauses: the recorder writes
        // the episode's row and the player's own slot, within a moment of
        // each other. Both, or the row looks like a listen from somewhere
        // else and the player moves to it.
        var refreshed = alarm!
        refreshed.playedPosition = 600
        refreshed.playedAt = Date()
        episodes.rows[refreshed.id] = refreshed
        PlaybackStateStore(defaults: defaults).save(PlaybackState(podcastId: refreshed.id, position: 600))
        player.mode = .podcast(podcast: refreshed)

        player.togglePlayPause()
        flush()

        XCTAssertEqual(engine.playCalls.count, 1, "the episode was loaded a second time")
        XCTAssertEqual(player.currentTime, 600, accuracy: 1)
    }

    // MARK: - Coming back to an episode

    func testAnEpisodeOpensWhereItWasLeft() {
        var heard = alarm!
        heard.playedPosition = 600

        let player = makePlayer()
        player.mode = .podcast(podcast: heard)

        // Three seconds back: you stopped listening slightly before you
        // stopped playing.
        XCTAssertEqual(player.currentTime, 597, accuracy: 0.5)

        player.togglePlayPause()
        flush()
        XCTAssertEqual(engine.lastPlayPosition ?? -1, 597, accuracy: 0.5)
    }

    func testAFinishedEpisodeOpensAtTheBeginning() {
        var finished = alarm!
        finished.playedPosition = 10_800
        finished.isPlayed = true

        let player = makePlayer()
        player.mode = .podcast(podcast: finished)

        XCTAssertTrue(player.offersReplay)

        player.togglePlayPause()
        flush()
        XCTAssertEqual(engine.lastPlayPosition, 0)
        XCTAssertFalse(player.offersReplay)
    }

    func testABookmarkBeatsTheStoredPosition() {
        var heard = alarm!
        heard.playedPosition = 600

        let player = makePlayer()
        player.play(heard, startingAt: 120)
        flush()

        XCTAssertEqual(engine.lastPlayPosition ?? -1, 120, accuracy: 0.5)
    }

    /// Both are written at the same moments, and the player's own slot is
    /// written a few seconds later - so it is the one to trust on launch.
    func testThePlayersOwnSlotBeatsTheEpisodeRecordOnLaunch() {
        var heard = alarm!
        heard.playedPosition = 600
        episodes.rows[heard.id] = heard
        PlaybackStateStore(defaults: defaults)
            .save(PlaybackState(podcastId: heard.id, position: 4_000))

        let player = makePlayer()
        player.restorePlaybackState()

        XCTAssertEqual(player.currentTime, 4_000, accuracy: 0.5)

        player.togglePlayPause()
        flush()
        XCTAssertEqual(engine.lastPlayPosition ?? -1, 4_000, accuracy: 0.5)
    }

    /// The other half of the same rule: a listen that happened on another
    /// device after this one last wrote its slot is the later of the two, and
    /// it is the one to open at.
    func testAPositionSyncedFromElsewhereBeatsAnOlderSlot() {
        var elsewhere = alarm!
        elsewhere.playedPosition = 5_700
        elsewhere.playedAt = Date()
        episodes.rows[elsewhere.id] = elsewhere

        PlaybackStateStore(defaults: defaults).save(
            PlaybackState(podcastId: elsewhere.id,
                          position: 3_120,
                          savedAt: Date(timeIntervalSinceNow: -3_600))
        )

        let player = makePlayer()
        player.restorePlaybackState()

        XCTAssertEqual(player.currentTime, 5_697, accuracy: 0.5)
    }

    // MARK: - Following the account

    /// The Mac listened to something else after the phone last did: the phone
    /// opens with that, where the Mac left it.
    func testTheAccountsLaterListenOpensInsteadOfThisDevicesOwn() {
        episodes.rows[alarm.id] = alarm
        PlaybackStateStore(defaults: defaults).save(
            PlaybackState(podcastId: alarm.id, position: 3_120, savedAt: Date(timeIntervalSinceNow: -3_600))
        )
        episodes.latest = listened(second, at: 1_800, secondsAgo: 60)

        let player = makePlayer()
        player.restorePlaybackState()

        XCTAssertEqual(player.title, "Emigracija")
        XCTAssertEqual(player.currentTime, 1_797, accuracy: 0.5)

        player.togglePlayPause()
        flush()
        XCTAssertEqual(engine.lastPlayPosition ?? -1, 1_797, accuracy: 0.5)
    }

    func testThisDevicesLaterListenStays() {
        episodes.rows[alarm.id] = alarm
        PlaybackStateStore(defaults: defaults).save(PlaybackState(podcastId: alarm.id, position: 3_120))
        episodes.latest = listened(second, at: 1_800, secondsAgo: 3_600)

        let player = makePlayer()
        player.restorePlaybackState()

        XCTAssertEqual(player.title, "Alarm")
        XCTAssertEqual(player.currentTime, 3_120, accuracy: 0.5)
    }

    /// Closing the player says there is nothing to come back to. A listen
    /// from before that does not bring it back.
    func testClosingThePlayerIsNotUndoneByAnOlderListen() {
        PlaybackStateStore(defaults: defaults).clear()
        episodes.latest = listened(second, at: 1_800, secondsAgo: 3_600)

        let player = makePlayer()
        player.restorePlaybackState()

        XCTAssertNil(player.mode)
        XCTAssertFalse(player.isPresented)
    }

    /// Nothing playing here, and a listen arrives from elsewhere: the player
    /// follows it without anyone having to relaunch.
    func testAnIdlePlayerFollowsAListenThatArrives() {
        episodes.rows[alarm.id] = alarm
        PlaybackStateStore(defaults: defaults).save(
            PlaybackState(podcastId: alarm.id, position: 3_120, savedAt: Date(timeIntervalSinceNow: -7_200))
        )
        let player = makePlayer()
        player.restorePlaybackState()
        XCTAssertEqual(player.title, "Alarm")

        episodes.latest = listened(second, at: 1_800, secondsAgo: 10)
        storeChanges.send(())
        flush()

        XCTAssertEqual(player.title, "Emigracija")
        XCTAssertEqual(player.currentTime, 1_797, accuracy: 0.5)
        XCTAssertTrue(engine.playCalls.isEmpty, "following must not start anything")
    }

    /// A position adopted from another device is not a listen here, and must
    /// not be written down as one: the write would carry this moment's date
    /// and hand this device the account's newest listen over the device that
    /// actually listened.
    func testAPositionAdoptedFromElsewhereIsNotWrittenDownAsAListen() {
        let recorder = ListeningRecorder(engine: engine,
                                         progressStore: progress,
                                         playbackState: PlaybackStateStore(defaults: defaults),
                                         notifications: notifications)
        recorder.start()

        let player = makePlayer(recorder: recorder)
        player.mode = .podcast(podcast: alarm)
        player.togglePlayPause()
        flush()
        engine.advance(to: 600)
        flush()
        engine.stopPlaying()
        flush()
        XCTAssertEqual(progress.calls.count, 1, "the pause is written down")

        listened(alarm, at: 5_400, secondsAgo: 0)
        storeChanges.send(())
        flush()
        XCTAssertEqual(engine.seekCalls.last ?? -1, 5_397, accuracy: 0.5)

        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(progress.calls.count, 1, "nothing was listened to here")
    }

    /// What is playing here is the truth; another device does not take it
    /// over mid-listen.
    func testAPlayingPlayerDoesNotFollow() {
        let player = makePlayer()
        player.mode = .podcast(podcast: alarm)
        player.togglePlayPause()
        flush()

        episodes.latest = listened(second, at: 1_800, secondsAgo: 0)
        storeChanges.send(())
        flush()

        XCTAssertEqual(player.title, "Alarm")
        XCTAssertEqual(engine.playCalls.count, 1)
    }

    /// Paused on the phone a few minutes from the end, and the Mac carries
    /// on: the paused phone moves to where the Mac got, and moves the engine
    /// with it, so play picks up there and not where the phone stopped.
    func testAPausedPlayerFollowsALaterPositionOnTheSameEpisode() {
        let player = makePlayer()
        player.mode = .podcast(podcast: alarm)
        player.togglePlayPause()
        flush()
        engine.advance(to: 3_000)
        flush()
        engine.stopPlaying()
        flush()

        listened(alarm, at: 5_400, secondsAgo: 0)
        storeChanges.send(())
        flush()

        XCTAssertEqual(engine.seekCalls.last ?? -1, 5_397, accuracy: 0.5)
        XCTAssertEqual(player.currentTime, 5_397, accuracy: 0.5)
    }

    /// A synced finish stays visible and offers an explicit replay.
    func testAnEpisodeFinishedElsewhereOffersReplay() {
        episodes.rows[alarm.id] = alarm
        PlaybackStateStore(defaults: defaults).save(
            PlaybackState(podcastId: alarm.id, position: 10_560, savedAt: Date(timeIntervalSinceNow: -600))
        )
        let player = makePlayer()
        player.restorePlaybackState()
        XCTAssertEqual(player.title, "Alarm")

        var finished = listened(alarm, at: 10_800, secondsAgo: 0)
        finished.isPlayed = true
        episodes.rows[alarm.id] = finished
        storeChanges.send(())
        flush()

        XCTAssertNotNil(player.mode)
        XCTAssertTrue(player.isPresented)
        XCTAssertTrue(player.offersReplay)
        player.togglePlayPause()
        flush()
        XCTAssertEqual(engine.lastPlayPosition, 0)
    }

    func testAnEpisodeFinishedElsewhereOffersReplayOnLaunch() {
        var finished = listened(alarm, at: 10_800, secondsAgo: 0)
        finished.isPlayed = true
        episodes.rows[alarm.id] = finished
        PlaybackStateStore(defaults: defaults).save(
            PlaybackState(podcastId: alarm.id, position: 10_560, savedAt: Date(timeIntervalSinceNow: -600))
        )

        let player = makePlayer()
        player.restorePlaybackState()

        XCTAssertNotNil(player.mode)
        XCTAssertTrue(player.isPresented)
        XCTAssertTrue(player.offersReplay)
    }

    /// Finished on this device is not finished elsewhere: the player stays.
    func testAnEpisodeFinishedHereStays() {
        var finished = listened(alarm, at: 10_800, secondsAgo: 60)
        finished.isPlayed = true
        episodes.rows[alarm.id] = finished
        PlaybackStateStore(defaults: defaults).save(PlaybackState(podcastId: alarm.id, position: 10_800))

        let player = makePlayer()
        player.restorePlaybackState()
        storeChanges.send(())
        flush()

        XCTAssertEqual(player.title, "Alarm")
    }

    func testLoadedEpisodeAtLastSecondRestartsWithoutHidingPlayer() {
        let player = makePlayer()
        player.mode = .podcast(podcast: alarm)
        player.togglePlayPause()
        flush()
        // Actual file duration can be shorter than the feed's estimate.
        engine.reportDuration(7_200)
        engine.advance(to: 7_199)
        engine.stopPlaying()
        flush()

        XCTAssertTrue(player.offersReplay)
        XCTAssertEqual(player.playButtonSymbol, "arrow.counterclockwise")
        player.togglePlayPause()
        flush()
        XCTAssertEqual(engine.lastPlayPosition, 0)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertTrue(player.isPresented)
        XCTAssertFalse(player.offersReplay)
    }

    func testPausedLoadedEpisodeAdoptsSyncedFinishAndReplays() {
        let player = makePlayer()
        player.mode = .podcast(podcast: alarm)
        player.togglePlayPause()
        flush()
        engine.advance(to: 600)
        engine.stopPlaying()
        flush()

        listened(alarm, at: 10_799, secondsAgo: 0)
        storeChanges.send(())
        flush()
        XCTAssertTrue(player.isPresented)
        XCTAssertTrue(player.offersReplay)
        player.togglePlayPause()
        flush()
        XCTAssertEqual(engine.lastPlayPosition, 0)
    }

    func testPreviouslyHeardEpisodePausedDuringReplayStillResumes() {
        var heard = alarm!
        heard.isPlayed = true
        let player = makePlayer()
        player.mode = .podcast(podcast: heard)
        player.togglePlayPause()
        flush()
        engine.advance(to: 600)
        engine.stopPlaying()
        flush()

        XCTAssertFalse(player.offersReplay)
        player.togglePlayPause()
        flush()
        XCTAssertEqual(engine.playCalls.count, 1)
        XCTAssertEqual(player.currentTime, 600)
    }

    /// The final ten seconds are past the show-end threshold. It is
    /// still a pause: pressing play again carries on, it does not rewind.
    func testPausingInTheClosingCreditsCarriesOn() {
        let player = makePlayer()
        player.mode = .podcast(podcast: alarm)
        player.togglePlayPause()
        flush()
        engine.advance(to: 10_790)
        engine.stopPlaying()
        flush()

        XCTAssertTrue(alarm.hasReachedEnd(at: 10_790))
        XCTAssertFalse(player.offersReplay)
        XCTAssertEqual(player.playButtonSymbol, "play.fill")
        player.togglePlayPause()
        flush()
        XCTAssertEqual(player.currentTime, 10_790, accuracy: 0.5)
    }

    func testSeekingBackFromEndRemovesReplayOffer() {
        let player = makePlayer()
        player.mode = .podcast(podcast: alarm)
        player.togglePlayPause()
        flush()
        engine.advance(to: 10_800)
        engine.stopPlaying()
        flush()
        XCTAssertTrue(player.offersReplay)
        player.seek(to: 600)
        flush()
        XCTAssertFalse(player.offersReplay)
    }

    // MARK: - Helpers

    private func makePlayer(recorder: ListeningRecorder? = nil) -> PlayerViewModel {
        PlayerViewModel(
            engine: engine,
            playbackState: PlaybackStateStore(defaults: defaults),
            episodes: episodes,
            recorder: recorder ?? ListeningRecorder(engine: engine,
                                                    progressStore: ProgressSpy(),
                                                    playbackState: PlaybackStateStore(defaults: defaults),
                                                    notifications: NotificationCenter()),
            storeChanges: storeChanges.eraseToAnyPublisher()
        )
    }

    /// An episode as another device left it.
    @discardableResult
    private func listened(_ episode: Podcast, at position: TimeInterval, secondsAgo: TimeInterval) -> Podcast {
        var copy = episode
        copy.playedPosition = position
        copy.playedAt = Date(timeIntervalSinceNow: -secondsAgo)
        episodes.rows[copy.id] = copy
        return copy
    }

    private func makeEpisode(title: String, show: Show, duration: String) -> Podcast {
        var podcast = Podcast(show: show)
        podcast.id = UUID()
        podcast.title = title
        podcast.podcastUrl = "https://example.com/\(title).mp3"
        podcast.itunesDuration = duration
        return podcast
    }

    /// The view model takes everything from the engine on the main queue, a
    /// runloop later. This lets those deliveries land before the assertions.
    private func flush() {
        let delivered = expectation(description: "main queue drained")
        DispatchQueue.main.async { delivered.fulfill() }
        wait(for: [delivered], timeout: 1)
    }
}

// MARK: - Writing a listen down

/// Everything about when a listen is written down, against the engine alone —
/// no player view model, no screen. That is the point: the car starts the app
/// with no phone window, and the listen still has to be written.
final class ListeningRecorderTests: XCTestCase {

    private var engine: FakePlaybackEngine!
    private var progress: ProgressSpy!
    private var defaults: UserDefaults!
    private var notifications: NotificationCenter!
    private var recorder: ListeningRecorder!

    private var alarm: Podcast!
    private var second: Podcast!

    override func setUpWithError() throws {
        engine = FakePlaybackEngine()
        progress = ProgressSpy()
        notifications = NotificationCenter()
        defaults = UserDefaults(suiteName: "ListeningRecorderTests")
        defaults.removePersistentDomain(forName: "ListeningRecorderTests")

        recorder = ListeningRecorder(engine: engine,
                                     progressStore: progress,
                                     playbackState: PlaybackStateStore(defaults: defaults),
                                     notifications: notifications)
        recorder.start()

        alarm = episode("Alarm", duration: "3:00:00")
        second = episode("Emigracija", duration: "2:00:00")
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: "ListeningRecorderTests")
    }

    /// The car: resumed at 57:45, a quarter of an hour of driving, the cable
    /// pulled. iOS pauses the audio, and that pause is what gets written.
    func testAListenInTheCarIsWrittenDownWhenTheCableIsPulled() {
        engine.play(.podcast(alarm), startingAt: 3_465)
        engine.advance(to: 4_365)
        engine.stopPlaying()

        XCTAssertEqual(progress.calls.last?.id, alarm.id)
        XCTAssertEqual(progress.calls.last?.position ?? 0, 4_365, accuracy: 1)
        XCTAssertEqual(PlaybackStateStore(defaults: defaults).saved?.position ?? 0, 4_365, accuracy: 1)
    }

    func testSwitchingEpisodesWritesDownWhereTheFirstGotTo() {
        engine.play(.podcast(alarm), startingAt: nil)
        engine.advance(to: 600)

        engine.play(.podcast(second), startingAt: nil)

        XCTAssertEqual(progress.calls.count, 1)
        XCTAssertEqual(progress.calls.first?.id, alarm.id)
        XCTAssertEqual(progress.calls.first?.position ?? 0, 600, accuracy: 1)
        XCTAssertEqual(progress.calls.first?.hasFinished, false)
    }

    func testSwitchingToRadioStillKeepsTheEpisodePosition() {
        engine.play(.podcast(alarm), startingAt: nil)
        engine.advance(to: 900)

        engine.play(.radio(url: URL(string: "https://example.com/stream")!), startingAt: nil)

        XCTAssertEqual(progress.calls.first?.id, alarm.id)
        XCTAssertEqual(progress.calls.first?.position ?? 0, 900, accuracy: 1)
    }

    /// A position in a stream means nothing an hour later, and there is no
    /// episode to write it against.
    func testLiveRadioWritesNothingDown() {
        engine.play(.radio(url: URL(string: "https://example.com/stream")!), startingAt: nil)
        engine.advance(to: 300)
        engine.stopPlaying()

        XCTAssertTrue(progress.calls.isEmpty)
    }

    /// The same episode handed to the engine again - rebuilt after another
    /// app took the audio - is not a change of episode, and the reset to
    /// zero while it reopens is not a position.
    func testTheSameEpisodeAgainIsNotASwitch() {
        engine.play(.podcast(alarm), startingAt: nil)
        engine.advance(to: 600)

        engine.play(.podcast(alarm), startingAt: 600)

        XCTAssertTrue(progress.calls.isEmpty)
    }

    /// The seek lands within a second of what was asked for, so the position
    /// that comes back is not the number that was adopted - and it is still
    /// not a listen.
    func testAPositionAdoptedIsNotAListenEvenWhenTheSeekLandsNearby() {
        engine.play(.podcast(alarm), startingAt: nil)
        engine.advance(to: 600)
        engine.stopPlaying()
        XCTAssertEqual(progress.calls.count, 1)

        recorder.noteAdopted(position: 5_397)
        engine.advance(to: 5_398)
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(progress.calls.count, 1)
    }

    /// And when the seek does not land at all, so the old position comes back.
    func testAFailedSeekAfterAdoptingWritesNothingEither() {
        engine.play(.podcast(alarm), startingAt: nil)
        engine.advance(to: 600)
        engine.stopPlaying()

        recorder.noteAdopted(position: 5_397)
        engine.advance(to: 600)
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(progress.calls.count, 1)
    }

    /// Listening here is what makes the position this device's own again.
    func testListeningAfterAdoptingIsWrittenDown() {
        engine.play(.podcast(alarm), startingAt: nil)
        engine.advance(to: 600)
        engine.stopPlaying()

        recorder.noteAdopted(position: 5_397)
        engine.play(.podcast(alarm), startingAt: 5_397)
        engine.advance(to: 5_460)
        engine.stopPlaying()

        XCTAssertEqual(progress.calls.count, 2)
        XCTAssertEqual(progress.calls.last?.position ?? 0, 5_460, accuracy: 1)
    }

    /// Fifteen seconds from a button is as much a decision as a drag, and
    /// the press may never pass through a screen of ours at all - the lock
    /// screen and the car go straight to the engine. So the engine announces
    /// every move a person makes, and the recorder listens there.
    func testASkipAfterAdoptingIsWrittenDown() {
        engine.play(.podcast(alarm), startingAt: nil)
        engine.advance(to: 600)
        engine.stopPlaying()

        recorder.noteAdopted(position: 5_397)
        engine.advance(to: 5_397)
        engine.skip(by: 15)
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(progress.calls.count, 2)
        XCTAssertEqual(progress.calls.last?.position ?? 0, 5_412, accuracy: 1)
    }

    /// Dragging the scrubber is somebody here, and is written down.
    func testAMoveByHandIsWrittenDown() {
        engine.play(.podcast(alarm), startingAt: nil)
        engine.advance(to: 600)
        engine.stopPlaying()

        recorder.noteAdopted(position: 5_397)
        recorder.noteMovedByHand(to: 4_000)
        engine.advance(to: 4_000)
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(progress.calls.count, 2)
        XCTAssertEqual(progress.calls.last?.position ?? 0, 4_000, accuracy: 1)
    }

    /// For what is not caught as it happens: the system ending the app
    /// mid-listen, or a crash.
    func testAMinuteOfListeningIsWrittenWithoutAPause() {
        engine.play(.podcast(alarm), startingAt: 1_000)
        engine.advance(to: 1_030)
        XCTAssertTrue(progress.calls.isEmpty)

        engine.advance(to: 1_061)
        XCTAssertEqual(progress.calls.count, 1)
        XCTAssertEqual(progress.calls.last?.position ?? 0, 1_061, accuracy: 1)

        engine.advance(to: 1_100)
        XCTAssertEqual(progress.calls.count, 1, "the next minute counts from the last write")
    }

    func testGoingToTheBackgroundWritesDown() {
        engine.play(.podcast(alarm), startingAt: nil)
        engine.advance(to: 45)

        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(progress.calls.last?.position ?? 0, 45, accuracy: 1)
    }

    /// Closing the player stops the engine, and the stop is written before
    /// the player clears what to reopen - not a runloop later, after it.
    func testStoppingWritesDownBeforeAnythingIsCleared() {
        engine.play(.podcast(alarm), startingAt: nil)
        engine.advance(to: 700)

        engine.stop()
        XCTAssertEqual(progress.calls.last?.position ?? 0, 700, accuracy: 1)

        PlaybackStateStore(defaults: defaults).clear()
        XCTAssertNil(PlaybackStateStore(defaults: defaults).saved)
    }

    /// Paused, then the app goes away an hour later: nothing moved, so
    /// nothing is written. A second write would only change the date, and the
    /// date decides which device listened last.
    func testAPauseIsNotWrittenAgainWhenNothingMoved() {
        engine.play(.podcast(alarm), startingAt: nil)
        engine.advance(to: 3_000)
        engine.stopPlaying()
        XCTAssertEqual(progress.calls.count, 1)

        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        engine.stop()

        XCTAssertEqual(progress.calls.count, 1)
    }

    func testStoppingPastTheEndMarksItHeard() {
        engine.play(.podcast(alarm), startingAt: nil)
        engine.advance(to: 10_781)
        engine.stopPlaying()

        XCTAssertEqual(progress.calls.last?.hasFinished, true)
    }

    func testMeasuredLastSecondIsRecordedAsFinished() {
        var short = alarm!
        short.show = .ostalo
        engine.play(.podcast(short), startingAt: nil)
        engine.reportDuration(3_600)
        engine.advance(to: 3_599)
        engine.stopPlaying()
        XCTAssertEqual(progress.calls.last?.hasFinished, true)
    }

    func testMovingToZeroDoesNotWriteTheOldEndPosition() {
        engine.play(.podcast(alarm), startingAt: nil)
        engine.advance(to: 600)
        engine.stopPlaying()
        recorder.noteAdopted(position: 10_799)
        engine.advance(to: 10_799)
        engine.moveByHand(to: 0)
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(progress.calls.count, 1)
    }

    func testStoppingBeforeTheEndDoesNotMarkItHeard() {
        engine.play(.podcast(alarm), startingAt: nil)
        engine.advance(to: 5_000)
        engine.stopPlaying()

        XCTAssertEqual(progress.calls.last?.hasFinished, false)
    }

    private func episode(_ title: String, duration: String) -> Podcast {
        var podcast = Podcast(show: .alarmSaDaskomIMladjom)
        podcast.id = UUID()
        podcast.title = title
        podcast.podcastUrl = "https://example.com/\(title).mp3"
        podcast.itunesDuration = duration
        return podcast
    }
}

// MARK: - Doubles

/// An engine with no player behind it. It reports what it is told to report,
/// and writes down what it was asked to do.
private final class FakePlaybackEngine: PlaybackEngineType {

    private let sourceSubject = CurrentValueSubject<PlaybackSource?, Never>(nil)
    private let playingSubject = CurrentValueSubject<Bool, Never>(false)
    private let bufferingSubject = CurrentValueSubject<Bool, Never>(false)
    private let timeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let trackSubject = CurrentValueSubject<LiveTrack?, Never>(nil)
    private let movedSubject = PassthroughSubject<TimeInterval, Never>()

    private(set) var playCalls: [(source: PlaybackSource, position: TimeInterval?)] = []
    /// Flattened, so a test can ask "was it started from nowhere in
    /// particular" without going through two layers of optional.
    var lastPlayPosition: TimeInterval? { playCalls.last?.position ?? nil }
    private(set) var seekCalls: [TimeInterval] = []
    private(set) var toggleCount = 0
    private(set) var stopCount = 0

    var source: PlaybackSource? { sourceSubject.value }
    var hasContent: Bool { source != nil }
    var duration: TimeInterval { durationSubject.value }
    var isLive: Bool { source?.isLive ?? false }
    var progress: Double {
        let duration = durationSubject.value
        guard duration > 0 else { return 0 }
        return timeSubject.value / duration
    }

    var sourcePublisher: AnyPublisher<PlaybackSource?, Never> { sourceSubject.eraseToAnyPublisher() }
    var isPlayingPublisher: AnyPublisher<Bool, Never> { playingSubject.eraseToAnyPublisher() }
    var isBufferingPublisher: AnyPublisher<Bool, Never> { bufferingSubject.eraseToAnyPublisher() }
    var currentTimePublisher: AnyPublisher<TimeInterval, Never> { timeSubject.eraseToAnyPublisher() }
    var durationPublisher: AnyPublisher<TimeInterval, Never> { durationSubject.eraseToAnyPublisher() }
    var liveTrackPublisher: AnyPublisher<LiveTrack?, Never> { trackSubject.eraseToAnyPublisher() }
    var movedByHandPublisher: AnyPublisher<TimeInterval, Never> { movedSubject.eraseToAnyPublisher() }

    func play(_ source: PlaybackSource, startingAt position: TimeInterval?) {
        playCalls.append((source, position))
        sourceSubject.send(source)
        timeSubject.send(position ?? 0)
        playingSubject.send(true)
    }

    func toggle() {
        toggleCount += 1
        playingSubject.send(!playingSubject.value)
    }

    func stop() {
        stopCount += 1
        playingSubject.send(false)
        sourceSubject.send(nil)
    }

    func seek(to time: TimeInterval, completion: (() -> Void)?) {
        seekCalls.append(time)
        timeSubject.send(time)
        completion?()
    }

    func skip(by seconds: TimeInterval) {
        moveByHand(to: timeSubject.value + seconds)
    }

    func moveByHand(to time: TimeInterval) {
        seek(to: time)
        movedSubject.send(max(0, time))
    }

    func switchToLocalFile(_ fileURL: URL) {}

    // Driving it from a test

    func advance(to time: TimeInterval) { timeSubject.send(time) }
    func reportDuration(_ duration: TimeInterval) { durationSubject.send(duration) }
    func stopPlaying() { playingSubject.send(false) }
}

private final class ProgressSpy: ProgressRecording {
    private(set) var calls: [(position: TimeInterval, hasFinished: Bool, id: UUID)] = []

    func recordProgress(position: TimeInterval, hasFinished: Bool, for id: UUID) {
        calls.append((position, hasFinished, id))
    }
}

private final class EpisodeStore: EpisodeLookup {
    var rows: [UUID: Podcast] = [:]
    /// What the account listened to last, as the repository would answer.
    var latest: Podcast?

    func podcast(with id: UUID) -> Podcast? { rows[id] }
    func lastListened() -> Podcast? { latest }
}

// MARK: - What the stream announces

/// One string arrives from the encoder and the screen either shows it or does
/// not. Everything here is that decision.
final class LiveTrackTests: XCTestCase {

    func testArtistAndTitleAreSplitOnTheDash() {
        let track = LiveTrack(raw: "Leonard Cohen - Light As The Breeze")
        XCTAssertEqual(track?.artist, "Leonard Cohen")
        XCTAssertEqual(track?.title, "Light As The Breeze")
    }

    func testAStringWithoutADashIsAllTitle() {
        let track = LiveTrack(raw: "Jingle")
        XCTAssertNil(track?.artist)
        XCTAssertEqual(track?.title, "Jingle")
    }

    /// The field name instead of the field: an untagged file, announced by an
    /// encoder that filled in what it had.
    func testTheWordArtistIsNotAnArtist() {
        XCTAssertNil(LiveTrack(raw: "artist - 14"))
        XCTAssertNil(LiveTrack(raw: "14 - artist"))
        XCTAssertNil(LiveTrack(raw: "Artist - Title"))
        XCTAssertNil(LiveTrack(raw: "unknown"))
    }

    func testTheStationNameSaysNothingNewAndIsDropped() {
        XCTAssertNil(LiveTrack(raw: "Daško i Mlađa"))
        XCTAssertNil(LiveTrack(raw: "  "))
        XCTAssertNil(LiveTrack(raw: "https://stream.daskoimladja.com"))
    }

    /// A number is a perfectly good song title when it arrives as one.
    func testANumericTitleFromARealArtistSurvives() {
        let track = LiveTrack(raw: "Smashing Pumpkins - 1979")
        XCTAssertEqual(track?.title, "1979")
    }
}


/// Exercise AVPlayer itself at EOF, not just the presentation test double.
final class PlaybackReplayTests: XCTestCase {
    func testActualPlayerCanResumeAndExplicitlyReplayAfterEOF() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        var wave = Data()
        func text(_ value: String) { wave.append(contentsOf: value.utf8) }
        func word(_ value: UInt16) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { wave.append(contentsOf: $0) }
        }
        func number(_ value: UInt32) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { wave.append(contentsOf: $0) }
        }
        let bytes: UInt32 = 44_100 * 4 * 2
        text("RIFF"); number(36 + bytes); text("WAVEfmt "); number(16)
        word(1); word(1); number(44_100); number(88_200); word(2); word(16)
        text("data"); number(bytes); wave.append(Data(count: Int(bytes)))
        try wave.write(to: url)

        let engine = PlaybackEngine.shared
        var subscriptions = Set<AnyCancellable>()
        defer {
            subscriptions.removeAll()
            engine.stop()
            try? FileManager.default.removeItem(at: url)
        }
        var episode = Podcast(show: .ostalo)
        episode.id = UUID()
        episode.podcastUrl = url.absoluteString
        episode.itunesDuration = "0:04"

        let ended = expectation(description: "AVPlayer reaches EOF")
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .prefix(1)
            .sink { _ in ended.fulfill() }
            .store(in: &subscriptions)
        engine.play(.podcast(episode), startingAt: 3)
        wait(for: [ended], timeout: 15)

        let resumed = expectation(description: "Remote-style resume restarts at zero")
        engine.isPlayingPublisher
            .filter { $0 && engine.currentTime < 1 }
            .prefix(1)
            .sink { _ in resumed.fulfill() }
            .store(in: &subscriptions)
        engine.resume()
        wait(for: [resumed], timeout: 10)
        engine.pause()

        let bookmark = expectation(description: "Explicit near-end bookmark keeps its position")
        engine.isPlayingPublisher
            .filter { $0 && engine.currentTime >= 3 }
            .prefix(1)
            .sink { _ in bookmark.fulfill() }
            .store(in: &subscriptions)
        engine.play(.podcast(episode), startingAt: 3)
        wait(for: [bookmark], timeout: 10)
        engine.pause()

        let positioned = expectation(description: "Seek back to EOF")
        engine.seek(to: engine.duration) {
            XCTAssertTrue(Thread.isMainThread)
            positioned.fulfill()
        }
        wait(for: [positioned], timeout: 10)

        let replayed = expectation(description: "Explicit replay starts at zero")
        engine.isPlayingPublisher
            .filter { $0 && engine.currentTime < 1 }
            .prefix(1)
            .sink { _ in replayed.fulfill() }
            .store(in: &subscriptions)
        engine.play(.podcast(episode), startingAt: 0)
        wait(for: [replayed], timeout: 10)

        // A newer seek replaces where the older one was going. It does not
        // replace the fact that somebody asked to start playing on arrival,
        // and the player it was asked of is still the one that is loaded -
        // so control still comes back. Dropping this left a tap on skip
        // during a stream's first second with a loaded, silent player.
        engine.pause()
        let superseded = expectation(description: "A superseded seek still hands control back")
        engine.seek(to: 1) { superseded.fulfill() }
        engine.seek(to: 2)
        wait(for: [superseded], timeout: 10)

        let obsolete = expectation(description: "A stopped player's seek cannot resume playback")
        obsolete.isInverted = true
        engine.seek(to: 2) { obsolete.fulfill() }
        engine.stop()
        wait(for: [obsolete], timeout: 0.5)
        XCTAssertNil(engine.source)
        XCTAssertFalse(engine.isPlaying)
    }
}
