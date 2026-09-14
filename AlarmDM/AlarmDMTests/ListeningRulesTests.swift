//
//  ListeningRulesTests.swift
//  AlarmDMTests
//
//  The rules that decide where an episode ends, when it counts as heard, and
//  where pressing play picks it up. All of it is arithmetic over a value type,
//  so none of it needs a player, a store or a screen.
//

import XCTest
@testable import AlarmDM

final class ListeningRulesTests: XCTestCase {

    // MARK: - Where the show ends

    /// Both conditions have to hold, so the later of the two settles it. Three
    /// hours of Alarm: ninety-five percent is eight minutes before the credits
    /// begin, so the credits are the line.
    func testLongEpisodeEndsAtTheCredits() {
        let episode = makeEpisode(duration: "3:00:00", outro: 20)
        XCTAssertEqual(episode.endOfShow, 10_780, accuracy: 0.5)
    }

    /// Five minutes: ninety-five percent falls after the credits have started,
    /// so the percentage is the line and the credits are not reached.
    func testShortEpisodeEndsAtNinetyFivePercent() {
        let episode = makeEpisode(duration: "5:00", outro: 20)
        XCTAssertEqual(episode.endOfShow, 285, accuracy: 0.5)
    }

    /// Nothing measured for the show: the episode ends where the file does.
    func testUnmeasuredShowEndsAtTheFile() {
        let episode = makeEpisode(show: .ostalo, duration: "1:00:00", outro: nil)
        XCTAssertEqual(episode.endOfShow, 3_600, accuracy: 0.5)
    }

    func testEpisodeWithoutADurationHasNoEnd() {
        let episode = makeEpisode(duration: "", outro: 20)
        XCTAssertEqual(episode.endOfShow, 0)
    }

    // MARK: - Whose figure for the credits

    func testBackendFigureWinsOverTheShow() {
        let episode = makeEpisode(show: .alarmSaDaskomIMladjom, duration: "1:00:00", outro: 45)
        XCTAssertEqual(episode.outro, 45)
    }

    /// Zero from the backend means unmeasured, not measured-as-none, so it does
    /// not overrule a show the app already knows about.
    func testBackendZeroFallsBackToTheShow() {
        let episode = makeEpisode(show: .ljudiIzPodzemlja, duration: "1:00:00", outro: 0)
        XCTAssertEqual(episode.outro, 5)
    }

    func testMissingFigureFallsBackToTheShow() {
        let episode = makeEpisode(show: .unutrasnjaEmigracija, duration: "2:00:00", outro: nil)
        XCTAssertEqual(episode.outro, 20)
    }

    // MARK: - Where play picks up

    func testResumesAFewSecondsBeforeWhereItStopped() {
        let episode = makeEpisode(duration: "3:00:00", outro: 20, playedPosition: 600)
        XCTAssertEqual(episode.resumePosition ?? -1, 597, accuracy: 0.5)
    }

    /// The first seconds are quicker to hear again than to think about.
    func testTheFirstSecondsAreNotAPositionWorthReturningTo() {
        let episode = makeEpisode(duration: "3:00:00", outro: 20, playedPosition: 15)
        XCTAssertNil(episode.resumePosition)
    }

    /// What is stored for a finished episode is a record of the last listen,
    /// not an invitation to sit through the credits again.
    func testAFinishedEpisodeStartsOver() {
        let episode = makeEpisode(duration: "3:00:00", outro: 20, playedPosition: 10_790, isPlayed: true)
        XCTAssertNil(episode.resumePosition)
    }

    /// Past the end of the show but never marked — the flag is written when
    /// playback stops, and this is the same answer without it.
    func testAPositionPastTheEndStartsOver() {
        let episode = makeEpisode(duration: "3:00:00", outro: 20, playedPosition: 10_790)
        XCTAssertNil(episode.resumePosition)
        XCTAssertTrue(episode.hasReachedEnd)
    }

    // MARK: - The line under a row

    func testNothingIsDrawnForAnEpisodeNeverStarted() {
        XCTAssertNil(makeEpisode(duration: "3:00:00", outro: 20).listeningProgress)
    }

    func testNothingIsDrawnForAFinishedEpisode() {
        let episode = makeEpisode(duration: "3:00:00", outro: 20, playedPosition: 10_780, isPlayed: true)
        XCTAssertNil(episode.listeningProgress)
    }

    func testHalfwayThroughIsHalfALine() {
        let episode = makeEpisode(duration: "3:00:00", outro: 20, playedPosition: 5_390)
        XCTAssertEqual(episode.listeningProgress ?? 0, 0.5, accuracy: 0.01)
    }

    /// A minute into three hours is still visible as something rather than as
    /// a line that was never drawn.
    func testAMinuteInIsStillVisible() {
        let episode = makeEpisode(duration: "3:00:00", outro: 20, playedPosition: 60)
        XCTAssertEqual(episode.listeningProgress ?? 0, 0.02, accuracy: 0.001)
    }

    // MARK: - Helper

    private func makeEpisode(show: Show = .alarmSaDaskomIMladjom,
                             duration: String,
                             outro: TimeInterval? = nil,
                             playedPosition: TimeInterval = 0,
                             isPlayed: Bool = false) -> Podcast {
        var podcast = Podcast(show: show)
        podcast.itunesDuration = duration
        podcast.outroSeconds = outro
        podcast.playedPosition = playedPosition
        podcast.isPlayed = isPlayed
        return podcast
    }
}
