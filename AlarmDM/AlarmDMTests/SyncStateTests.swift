//
//  SyncStateTests.swift
//  AlarmDMTests
//
//  The half of syncing this app owns: what happens to the rows once iCloud
//  has put them in the store. Which of two listens wins, which flags survive,
//  and whether the next decision reads what arrived or what was already held.
//
//  iCloud itself is not here. Whether a row leaves one device and reaches
//  another is Apple's machinery, over the network, on its own schedule; a test
//  of that needs two signed-in devices and minutes of waiting, and is a
//  different kind of test from these.
//

import XCTest
import Combine
import CoreData
import SwiftData
@testable import AlarmDM

// MARK: - Two devices, one episode

/// Two devices that both listen to an episode before either has heard from the
/// other each create a row for it. CloudKit has no unique constraint to stop
/// that, so both rows end up everywhere, and the repository has to make one
/// answer out of them.
final class SyncMergeTests: XCTestCase {

    private var database: AppDatabase!
    private var repository: PodcastRepository!
    private var episode: Podcast!

    private let earlier = Date(timeIntervalSince1970: 1_800_000_000)
    private var later: Date { earlier.addingTimeInterval(60) }

    override func setUp() {
        database = AppDatabase(inMemory: true)
        repository = PodcastRepository(database: database)
        episode = makeEpisode(title: "Alarm")
        repository.save(episode)
    }

    override func tearDown() {
        repository = nil
        database = nil
    }

    /// Reading takes the later listen, whichever row the store happens to
    /// return first.
    func testTheLaterListenIsWhatIsRead() {
        insertRow(position: 600, at: earlier)
        insertRow(position: 1_800, at: later)

        XCTAssertEqual(repository.latestPodcasts().first?.playedPosition, 1_800)
        XCTAssertEqual(repository.podcast(with: episode.id)?.playedPosition, 1_800)
    }

    /// A row that has never been played has no date, and a dated row beats
    /// it however far along the undated one claims to be.
    func testARowWithoutADateLosesToOneWithADate() {
        let undated = EpisodeStateEntity(podcastId: episode.id)
        undated.playedPosition = 5_000
        let dated = EpisodeStateEntity(podcastId: episode.id)
        dated.playedPosition = 300
        dated.playedAt = earlier

        XCTAssertTrue(EpisodeStateEntity.isNewer(dated, than: undated))
        XCTAssertFalse(EpisodeStateEntity.isNewer(undated, than: dated))
    }

    /// A list and a single episode read the same rows, so they have to give
    /// the same answer. They did not: the list took the newest row whole and
    /// an episode opened on its own OR-ed the flags, so an episode favourited
    /// on one device and listened to later on another was missing from the
    /// favourites list until its player had been opened.
    func testAListAndAnEpisodeAgreeOnAFavourite() {
        insertRow(position: 600, at: earlier, favourite: true)
        insertRow(position: 1_800, at: later, favourite: false)

        XCTAssertEqual(repository.latestPodcasts().first?.isFavorite, true)
        XCTAssertEqual(repository.podcast(with: episode.id)?.isFavorite, true)
    }

    func testAListAndAnEpisodeAgreeOnHavingBeenHeard() {
        insertRow(position: 10_790, at: earlier, played: true)
        insertRow(position: 60, at: later, played: false)

        XCTAssertEqual(repository.latestPodcasts().first?.isPlayed, true)
        XCTAssertEqual(repository.podcast(with: episode.id)?.isPlayed, true)
    }

    /// Reading is not writing: opening an episode used to fold its duplicates
    /// away and delete them, which is a store change in the middle of a read.
    func testReadingAnEpisodeLeavesTheRowsAlone() {
        insertRow(position: 600, at: earlier)
        insertRow(position: 1_800, at: later)

        _ = repository.podcast(with: episode.id)

        XCTAssertEqual(stateRows().count, 2)
    }

    /// The next write folds the two rows into one, so the duplicate does not
    /// travel back through iCloud forever.
    func testTheNextWriteLeavesOneRow() {
        insertRow(position: 600, at: earlier)
        insertRow(position: 1_800, at: later)

        repository.recordProgress(position: 1_900, hasFinished: false, for: episode.id)

        XCTAssertEqual(stateRows().count, 1)
        XCTAssertEqual(stateRows().first?.playedPosition, 1_900)
    }

    /// A position is a moment and the later moment wins; a favourite is a
    /// decision, and a decision made on either device stands.
    func testAFavouriteFromEitherDeviceSurvives() {
        insertRow(position: 600, at: earlier, favourite: true)
        insertRow(position: 1_800, at: later, favourite: false)

        repository.recordProgress(position: 1_900, hasFinished: false, for: episode.id)

        XCTAssertEqual(stateRows().first?.isFavorite, true)
    }

    /// Heard through on the phone, then opened for a minute on the Mac: still
    /// heard, even though the Mac's row is the newer one.
    func testHeardOnEitherDeviceStaysHeard() {
        insertRow(position: 10_790, at: earlier, played: true)
        insertRow(position: 60, at: later, played: false)

        let merged = repository.podcast(with: episode.id)

        XCTAssertEqual(merged?.isPlayed, true)
        XCTAssertEqual(merged?.playedPosition, 60)
        // Both rows are still there: folding them away is a write, and this
        // was a read. See testTheNextWriteLeavesOneRow.
        XCTAssertEqual(stateRows().count, 2)
    }

    /// The same rule on one device: starting a finished episode again does
    /// not make it unfinished.
    func testFinishingIsSticky() {
        repository.recordProgress(position: 10_790, hasFinished: true, for: episode.id)
        repository.recordProgress(position: 100, hasFinished: false, for: episode.id)

        let row = stateRows().first
        XCTAssertEqual(row?.isPlayed, true)
        XCTAssertEqual(row?.playedPosition, 100)
    }

    /// "Carry on" is the newest listen with somewhere left to go - one left
    /// sitting at the end does not push it out.
    func testCarryOnSkipsWhatWasLeftAtTheEnd() {
        let other = makeEpisode(title: "Emigracija")
        repository.save(other)

        repository.recordProgress(position: 600, hasFinished: false, for: episode.id)
        repository.recordProgress(position: 10_790, hasFinished: true, for: other.id)

        XCTAssertEqual(repository.lastListened()?.id, episode.id)
    }

    /// Heard through, then started again and left half an hour in. That is
    /// exactly what somebody is in the middle of, and it used to be dropped
    /// by the fetch before anything could look at where it had got to - so
    /// the car offered the next unfinished episode instead.
    func testCarryOnOffersAnEpisodeBeingHeardAgain() {
        let other = makeEpisode(title: "Emigracija")
        repository.save(other)

        repository.recordProgress(position: 600, hasFinished: false, for: other.id)
        repository.recordProgress(position: 10_790, hasFinished: true, for: episode.id)
        // Started again, and left twenty-five minutes in.
        repository.recordProgress(position: 1_500, hasFinished: false, for: episode.id)

        XCTAssertEqual(repository.lastListened()?.id, episode.id)
        XCTAssertEqual(repository.lastListened()?.resumePosition ?? -1, 1_497, accuracy: 0.5)
        // Still heard: starting it again does not undo that.
        XCTAssertEqual(repository.podcast(with: episode.id)?.isPlayed, true)
    }

    // MARK: Helpers

    /// A row as another device would have left it: written straight into the
    /// store, not through the repository.
    private func insertRow(position: Double, at date: Date?, favourite: Bool = false, played: Bool = false) {
        let row = EpisodeStateEntity(podcastId: episode.id, title: episode.title)
        row.playedPosition = position
        row.playedAt = date
        row.isFavorite = favourite
        row.isPlayed = played
        database.context.insert(row)
        XCTAssertNoThrow(try database.context.save())
    }

    private func stateRows() -> [EpisodeStateEntity] {
        let id = episode.id
        let descriptor = FetchDescriptor<EpisodeStateEntity>(predicate: #Predicate { $0.podcastId == id })
        return (try? database.context.fetch(descriptor)) ?? []
    }
}

// MARK: - Something else wrote to the store

/// What an import from iCloud looks like from inside the app: another writer
/// changing rows in the store this side has already read. Here the other
/// writer is a second container on the same files, as close to CloudKit's own
/// as a test gets without CloudKit.
///
/// These used to claim more than they showed. The first was meant to prove
/// that re-reading the store before a decision is what makes an arrived
/// position visible; it passes just the same with the re-read taken out,
/// because the repository keeps no rows between reads - it fetches every
/// time and hands out copies. So it is now a test of that: whatever the
/// repository reads, it reads fresh. It will fail the day something starts
/// holding on to rows, which is the day the re-read starts to matter.
final class StoreChangeTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreChangeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAReadAfterAnotherWriterSeesTheNewValue() {
        let phone = PodcastRepository(database: AppDatabase(storeDirectory: directory))
        let episode = makeEpisode(title: "Alarm")
        phone.save(episode)
        phone.recordProgress(position: 600, hasFinished: false, for: episode.id)
        XCTAssertEqual(phone.podcast(with: episode.id)?.playedPosition, 600)

        let otherDevice = PodcastRepository(database: AppDatabase(storeDirectory: directory))
        otherDevice.recordProgress(position: 5_400, hasFinished: false, for: episode.id)

        XCTAssertEqual(phone.podcast(with: episode.id)?.playedPosition, 5_400)
        XCTAssertEqual(phone.resumePosition(for: episode.id) ?? 0, 5_397, accuracy: 0.5)
    }

    /// What the store's change notice is actually for: screens hold copies
    /// they took when they appeared, and this is how they hear it is time to
    /// take new ones. Without it an arrived bookmark sits in the database
    /// while the list goes on showing the old one.
    func testTheRemoteChangeNoticeReachesTheScreens() {
        let database = AppDatabase(storeDirectory: directory)

        // Posted by hand: a store without CloudKit may not post it on its
        // own. What is under test is that the app passes it on.
        let noticed = expectation(description: "the database passed the change on")
        let subscription = database.didChangeRemotely.sink { noticed.fulfill() }
        NotificationCenter.default.post(name: .NSPersistentStoreRemoteChange, object: nil)
        wait(for: [noticed], timeout: 2)
        subscription.cancel()
    }
}

// MARK: - What iCloud will accept

/// iCloud refuses a model with a unique constraint, or with a required value
/// that has no default, and it refuses it when the store is opened. In the
/// app that refusal is caught and the store opens again without syncing: it
/// keeps working, and it never syncs again, and nothing on screen says so.
/// This opens the synced half exactly as the app does and fails where the
/// app would go quiet.
///
/// Needs the test to run inside the app, which carries the iCloud
/// entitlement. It writes nothing to iCloud: the store it opens is empty and
/// is thrown away afterwards.
final class SyncSchemaTests: XCTestCase {

    func testTheSyncedModelsAreAcceptableToICloud() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncSchemaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = AppDatabase.syncedConfiguration(at: directory.appendingPathComponent("Synced.store"))

        XCTAssertNoThrow(try ModelContainer(for: Schema(AppDatabase.syncedModels),
                                            configurations: configuration))
    }
}

// MARK: - Fixture

/// Three hours with twenty seconds of credits: the show ends at 10 780.
private func makeEpisode(title: String) -> Podcast {
    var podcast = Podcast(show: .alarmSaDaskomIMladjom)
    podcast.title = title
    podcast.itunesDuration = "3:00:00"
    podcast.outroSeconds = 20
    podcast.podcastUrl = "https://example.com/\(podcast.id).mp3"
    podcast.createdDate = Date()
    return podcast
}
