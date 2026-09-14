//
//  PlayerStateTests.swift
//  AlarmDMTests
//
//  What the player does when what it is playing changes: which position is
//  written down, which one is picked up, and which one wins when two of them
//  disagree. Driven by a fake engine, so none of it needs AVFoundation, a
//  file, or the network.
//

import XCTest
import Combine
@testable import AlarmDM

final class PlayerStateTests: XCTestCase {

    private var engine: FakePlaybackEngine!
    private var progress: ProgressSpy!
    private var episodes: EpisodeStore!
    private var defaults: UserDefaults!

    /// Three hours, so the credits settle where it ends: 3:00:00 minus twenty
    /// seconds is 10 780, comfortably past ninety-five percent.
    private var alarm: Podcast!
    /// A second episode, to switch to.
    private var second: Podcast!

    override func setUpWithError() throws {
        engine = FakePlaybackEngine()
        progress = ProgressSpy()
        episodes = EpisodeStore()

        defaults = UserDefaults(suiteName: "PlayerStateTests")
        defaults.removePersistentDomain(forName: "PlayerStateTests")

        alarm = makeEpisode(title: "Alarm", show: .alarmSaDaskomIMladjom, duration: "3:00:00")
        second = makeEpisode(title: "Emigracija", show: .unutrasnjaEmigracija, duration: "2:00:00")
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: "PlayerStateTests")
    }

    // MARK: - Leaving one episode for another

    func testSwitchingEpisodesWritesDownWhereTheFirstGotTo() {
        let player = makePlayer()

        player.mode = .podcast(podcast: alarm)
        player.togglePlayPause()
        engine.advance(to: 600)
        flush()

        player.mode = .podcast(podcast: second)

        XCTAssertEqual(progress.calls.count, 1)
        XCTAssertEqual(progress.calls.first?.id, alarm.id)
        XCTAssertEqual(progress.calls.first?.position ?? 0, 600, accuracy: 1)
        XCTAssertEqual(progress.calls.first?.hasFinished, false)
    }

    func testSwitchingToRadioStillKeepsTheEpisodePosition() {
        let player = makePlayer()

        player.mode = .podcast(podcast: alarm)
        player.togglePlayPause()
        engine.advance(to: 900)
        flush()

        player.mode = .radio(stream: URL(string: "https://example.com/stream"))

        XCTAssertEqual(progress.calls.first?.id, alarm.id)
        XCTAssertEqual(progress.calls.first?.position ?? 0, 900, accuracy: 1)
    }

    /// A position in a stream means nothing an hour later, and there is no
    /// episode to write it against.
    func testLiveRadioWritesNothingDown() {
        let player = makePlayer()

        player.mode = .radio(stream: URL(string: "https://example.com/stream"))
        player.togglePlayPause()
        engine.advance(to: 300)
        flush()
        engine.stopPlaying()
        flush()

        XCTAssertTrue(progress.calls.isEmpty)
    }

    /// The same episode arriving again as a refreshed row — a favourite
    /// toggled, a download finished — is not a swap.
    func testReselectingTheSameEpisodeLeavesPlaybackAlone() {
        let player = makePlayer()

        player.mode = .podcast(podcast: alarm)
        player.togglePlayPause()
        engine.advance(to: 600)
        flush()

        var refreshed = alarm!
        refreshed.isFavorite = true
        player.mode = .podcast(podcast: refreshed)

        XCTAssertEqual(player.currentTime, 600, accuracy: 1)
        XCTAssertTrue(progress.calls.isEmpty)
        XCTAssertEqual(engine.playCalls.count, 1)
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
        XCTAssertEqual(engine.lastPlayPosition ?? -1, 597, accuracy: 0.5)
    }

    func testAFinishedEpisodeOpensAtTheBeginning() {
        var finished = alarm!
        finished.playedPosition = 10_790
        finished.isPlayed = true

        let player = makePlayer()
        player.mode = .podcast(podcast: finished)

        XCTAssertEqual(player.currentTime, 0)

        player.togglePlayPause()
        XCTAssertNil(engine.lastPlayPosition)
    }

    func testABookmarkBeatsTheStoredPosition() {
        var heard = alarm!
        heard.playedPosition = 600

        let player = makePlayer()
        player.play(heard, startingAt: 120)

        XCTAssertEqual(engine.lastPlayPosition ?? -1, 120, accuracy: 0.5)
    }

    /// Both are written at the same moments, and the player's own slot is
    /// written a few seconds later — so it is the one to trust on launch.
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
        XCTAssertEqual(engine.lastPlayPosition ?? -1, 4_000, accuracy: 0.5)
    }

    // MARK: - Finishing

    func testStoppingPastTheEndMarksItHeard() {
        let player = makePlayer()

        player.mode = .podcast(podcast: alarm)
        player.togglePlayPause()
        engine.advance(to: 10_781)
        flush()
        engine.stopPlaying()
        flush()

        XCTAssertEqual(progress.calls.last?.hasFinished, true)
    }

    func testStoppingBeforeTheEndDoesNotMarkItHeard() {
        let player = makePlayer()

        player.mode = .podcast(podcast: alarm)
        player.togglePlayPause()
        engine.advance(to: 5_000)
        flush()
        engine.stopPlaying()
        flush()

        XCTAssertEqual(progress.calls.last?.hasFinished, false)
    }

    // MARK: - Helpers

    private func makePlayer() -> PlayerViewModel {
        PlayerViewModel(
            engine: engine,
            playbackState: PlaybackStateStore(defaults: defaults),
            progressStore: progress,
            episodes: episodes
        )
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

    private(set) var playCalls: [(source: PlaybackSource, position: TimeInterval?)] = []
    /// Flattened, so a test can ask "was it started from nowhere in
    /// particular" without going through two layers of optional.
    var lastPlayPosition: TimeInterval? { playCalls.last?.position ?? nil }
    private(set) var seekCalls: [TimeInterval] = []
    private(set) var toggleCount = 0
    private(set) var stopCount = 0

    var source: PlaybackSource? { sourceSubject.value }
    var hasContent: Bool { source != nil }
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

    func seek(to time: TimeInterval) {
        seekCalls.append(time)
        timeSubject.send(time)
    }

    func skip(by seconds: TimeInterval) {
        seek(to: timeSubject.value + seconds)
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

    func podcast(with id: UUID) -> Podcast? { rows[id] }
}
