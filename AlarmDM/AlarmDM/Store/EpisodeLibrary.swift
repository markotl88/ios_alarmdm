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
    /// downloaded — and the Preuzeto filter cannot see it.
    let didChange = PassthroughSubject<Void, Never>()

    /// Fires when the WiFi-only rule stopped a download, so the UI can offer to
    /// go ahead anyway or to drop the rule. The library refuses rather than
    /// deciding for the person — it has no way to ask.
    let downloadBlocked = PassthroughSubject<Podcast, Never>()

    private let repository = PodcastRepository.shared
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

    init(fileService: FileServiceProtocol = FileService(),
         podcastService: PodcastServiceProtocol = PodcastService(),
         database: AppDatabase = .shared) {
        self.fileService = fileService
        self.podcastService = podcastService

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
    /// the download starts and when it ends — never per tick, so a list is not
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

    /// Called by whoever wrote to the store outside this type — the player,
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
            didChange.send()
            return true
        case .failure(let error):
            AppLog.write(.library, "Error deleting download: \(error.localizedDescription)")
            return false
        }
    }
}
