//
//  EpisodeLibrary.swift
//  AlarmDM
//
//  Favouriting, downloading and deleting an episode touch both the file
//  system and the database, and every screen offers them. One place, so the
//  screens cannot drift apart.
//

import Foundation
import Combine

/// Writing down how far an episode has been listened to. One method, so the
/// player can be tested without a database behind it.
protocol ProgressRecording: AnyObject {
    func recordProgress(position: TimeInterval, hasFinished: Bool, for id: UUID)
}

/// Favouriting and deleting a download touch both the file system and the store,
/// and both the Radio tab and a show's list offer them. Kept in one place so
/// the two screens cannot drift apart.
final class EpisodeLibrary: ProgressRecording {

    static let shared = EpisodeLibrary()

    /// Fires whenever an episode's local state changes. Lists hold snapshots
    /// taken from the store when they appeared, so without this a download made
    /// from the player leaves every visible row still claiming it is not
    /// downloaded - and the Preuzeto filter cannot see it.
    let didChange = PassthroughSubject<Void, Never>()

    /// Fires when the WiFi-only rule stopped a download, so the UI can offer to
    /// go ahead anyway or to drop the rule. The library refuses rather than
    /// deciding for the person - it has no way to ask.
    let downloadBlocked = PassthroughSubject<Podcast, Never>()

    private let repository: PodcastRepository
    private let fileService: FileServiceProtocol
    private let podcastService: PodcastServiceProtocol
    private let settings = AppSettings.shared
    private let network = NetworkMonitor.shared

    /// Episodes with a download in flight. A row shows a ring for these, and a
    /// second tap cannot start the same download twice.
    private(set) var downloadsInFlight: Set<UUID> = []

    private var downloadProgress: [UUID: Double] = [:]
    private let progressSubject = PassthroughSubject<(id: UUID, progress: Double), Never>()

    /// Progress ticks, one stream for the whole app. Every consumer filters by
    /// episode id, so a row redraws only for its own download and the list is
    /// never rebuilt for someone else's.
    var progressPublisher: AnyPublisher<(id: UUID, progress: Double), Never> {
        progressSubject.eraseToAnyPublisher()
    }

    func progress(for id: UUID) -> Double { downloadProgress[id] ?? 0 }

    private var cancellables = Set<AnyCancellable>()

    /// Only to hand a finished file to whatever is playing - see
    /// adoptDownloadedFile. Nothing here starts or stops audio.
    private let engine: PlaybackEngineType

    init(fileService: FileServiceProtocol = FileService(),
         podcastService: PodcastServiceProtocol = PodcastService(),
         database: AppDatabase = .shared,
         engine: PlaybackEngineType = PlaybackEngine.shared,
         repository: PodcastRepository = .shared) {
        self.fileService = fileService
        self.podcastService = podcastService
        self.engine = engine
        self.repository = repository

        // A favourite marked on another device is a change to this list like
        // any other, and the screens already know what to do with didChange.
        database.didChangeRemotely
            .sink { [weak self] in self?.didChange.send() }
            .store(in: &cancellables)
    }

    func isDownloading(_ podcast: Podcast) -> Bool {
        downloadsInFlight.contains(podcast.id)
    }

    /// Downloads an episode and records the local file. `didChange` fires when
    /// the download starts and when it ends - never per tick, so a list is not
    /// rebuilt sixty times a minute; progress goes out on `progressPublisher`
    /// instead. On a metered connection this refuses and emits `downloadBlocked`
    /// unless `force` says the person has already chosen.
    ///
    /// Returns whether the download actually started, so a caller does not put
    /// itself into a downloading state for something that was refused.
    @discardableResult
    func download(_ podcast: Podcast,
                  force: Bool = false,
                  completion: ((Result<URL, Error>) -> Void)? = nil) -> Bool {
        guard !podcast.isDownloaded else { return false }
        guard !downloadsInFlight.contains(podcast.id) else { return false }
        guard let url = URL(string: podcast.podcastUrl) else {
            AppLog.write(.library, "Episode \(podcast.id) has no usable media URL")
            return false
        }

        if !force, settings.downloadsOverWiFiOnly, network.isMetered {
            downloadBlocked.send(podcast)
            return false
        }

        downloadsInFlight.insert(podcast.id)
        downloadProgress[podcast.id] = 0
        didChange.send()

        podcastService.downloadPodcasts(from: url, completion: { [weak self] result in
            guard let self else { return }
            self.downloadsInFlight.remove(podcast.id)
            self.downloadProgress[podcast.id] = nil

            if case .success(let location) = result {
                self.repository.setDownloadedFile(location.lastPathComponent, for: podcast.id)
                self.adoptDownloadedFile(location, for: podcast.id)
            } else if case .failure(let error) = result {
                AppLog.write(.library, "Error downloading episode: \(error.localizedDescription)")
            }

            self.didChange.send()
            completion?(result)
        }, progressHandler: { [weak self] value in
            guard let self else { return }
            // Throttled to whole percent steps, and hopped to main because the
            // session reports progress from its own queue.
            DispatchQueue.main.async {
                let previous = self.downloadProgress[podcast.id] ?? 0
                guard value >= previous + 0.01 || value >= 1 else { return }
                self.downloadProgress[podcast.id] = value
                self.progressSubject.send((id: podcast.id, progress: value))
            }
        })

        return true
    }

    /// Hands the file that just landed to the engine, when the episode it
    /// belongs to is the one playing.
    ///
    /// Here rather than on the player's download button, which is where it
    /// used to be. That button is one of five ways a download starts - a row
    /// in the Radio tab, a row in a show's list, and the two ways out of the
    /// metered-network alert are the others - and from any of those the
    /// engine went on pulling from the network with the finished file sitting
    /// on disk beside it. It caught up the next time that episode was opened,
    /// which is to say: not during the listen the download was for.
    ///
    /// The same shape as the listen that went unrecorded in the car. A thing
    /// that has to happen whenever a download finishes cannot live on a
    /// screen, because the screen is open in one of the five cases.
    private func adoptDownloadedFile(_ location: URL, for id: UUID) {
        guard case .podcast(let playing) = engine.source, playing.id == id else { return }
        engine.switchToLocalFile(location)
    }

    /// The same handover the other way: the file a listen was running on has
    /// been deleted, so the listen goes back to the network before it notices.
    ///
    /// Without it the audio runs to the end of what AVPlayer already holds
    /// and stops there, with a failed item and nothing on screen to explain
    /// it. Pressing play again recovers - a failed item is rebuilt, and the
    /// URL is resolved against a file system that no longer has the file -
    /// but by then the listen has been interrupted for no reason the person
    /// can see.
    ///
    /// `nil` means every episode: emptying the whole folder does not name
    /// one, and the only one that matters is whatever is playing.
    private func releaseDownloadedFile(for id: UUID?) {
        guard case .podcast(let playing) = engine.source else { return }
        if let id, playing.id != id { return }
        // It was playing from a file, not from the network. The value the
        // engine holds still says so - it was captured before the delete -
        // which is exactly the question being asked.
        guard playing.isDownloaded else { return }
        engine.switchToStream()
    }

    /// Empties the downloads folder and forgets every file in it.
    ///
    /// Here rather than in the settings screen, which is where it was: that
    /// screen reached past this type to the file service and the repository,
    /// so nothing knew a file had gone - including a listen that happened to
    /// be running on one of them.
    @discardableResult
    func deleteAllDownloads() -> Result<Int, FileServiceError> {
        let result = fileService.deleteAllDownloads()
        if case .success = result {
            repository.clearAllDownloadReferences()
            releaseDownloadedFile(for: nil)
            didChange.send()
        }
        return result
    }

    /// Called by whoever wrote to the store outside this type - the player,
    /// after a download finishes.
    func episodeDidChange() {
        didChange.send()
    }

    /// Where a listen got to, written down and announced. Through here rather
    /// than straight into the repository so the lists hear about it: an
    /// episode that has just been finished should carry its tick the moment
    /// the player is put down, not the next time the screen happens to fetch.
    func recordProgress(position: TimeInterval, hasFinished: Bool, for id: UUID) {
        repository.recordProgress(position: position, hasFinished: hasFinished, for: id)
        didChange.send()
    }

    func toggleFavourite(_ podcast: Podcast) {
        repository.setFavorite(!podcast.isFavorite, for: podcast.id)
        didChange.send()
    }

    /// Deleting while the episode is playing is safe: the player holds the file
    /// open and keeps reading it until it is done.
    @discardableResult
    func deleteDownload(_ podcast: Podcast) -> Bool {
        guard let fileName = podcast.fileUrl else { return false }

        switch fileService.deleteFile(with: fileName) {
        case .success:
            repository.clearDownloadReference(for: podcast.id)
            releaseDownloadedFile(for: podcast.id)
            didChange.send()
            return true
        case .failure(let error):
            AppLog.write(.library, "Error deleting download: \(error.localizedDescription)")
            return false
        }
    }
}
