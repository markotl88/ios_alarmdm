//
//  PlayerViewModel.swift
//  AlarmDM
//
//  A thin, observable façade over PlaybackEngine.shared. It owns the UI-only
//  concerns (presentation, download progress, Realm bookkeeping) and mirrors
//  playback state from the engine, so the phone UI and the CarPlay scene can
//  never disagree about what is playing.
//

import Foundation
import Combine
import RealmSwift
import AVFoundation

enum PlayerMode: Equatable, Identifiable {
    var id: UUID {
        switch self {
        case .radio:
            return UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        case .podcast(let podcast):
            return podcast.id
        }
    }

    case radio(stream: URL?)
    case podcast(podcast: Podcast)
}

final class PlayerViewModel: ObservableObject {

    // MARK: - Presentation state

    @Published var isPresented = false
    @Published var isExpanded = false

    // MARK: - Playback state (mirrored from the engine)

    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var title: String = ""
    @Published var subtitle: String = ""
    @Published private(set) var artworkName: String = "img_radio"
    @Published private(set) var isLive: Bool = false

    /// 0...1 position within the current episode. Live radio always reports 0.
    var playbackProgress: Double { engine.progress }

    // MARK: - Download state

    @Published var isDownloaded: Bool = false
    @Published var isDownloading: Bool = false
    /// Download progress, 0...1. Kept under this name because PlayerView binds to it.
    @Published var progress: Double = 0.0
    @Published var showDeleteButton: Bool = false
    @Published var showCheckmark: Bool = false

    @Published var mode: PlayerMode? {
        didSet {
            guard mode != oldValue else { return }
            applyMode()
        }
    }

    let id = UUID()

    // MARK: - Dependencies

    private let engine: PlaybackEngine
    private let fileService: FileServiceProtocol
    private let podcastService: PodcastServiceProtocol
    private let realm = try? Realm()
    private var cancellables = Set<AnyCancellable>()

    private var podcastId: UUID?
    private var podcast: Podcast?
    private var onlineStream: URL?

    // MARK: - Init

    init(mode: PlayerMode? = nil,
         engine: PlaybackEngine = .shared,
         podcastService: PodcastServiceProtocol = PodcastService(),
         fileService: FileServiceProtocol = FileService()) {

        self.engine = engine
        self.fileService = fileService
        self.podcastService = podcastService
        self.mode = mode

        bindEngine()
        if mode != nil { applyMode() }
    }

    /// Keeps the view model in step with whatever the engine is doing — including
    /// playback started from CarPlay or the lock screen.
    private func bindEngine() {
        engine.isPlayingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isPlaying = $0 }
            .store(in: &cancellables)

        engine.isBufferingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isBuffering = $0 }
            .store(in: &cancellables)

        // Rounded and de-duplicated: the engine ticks twice a second, and every
        // distinct value re-renders each view observing this object.
        engine.currentTimePublisher
            .map { $0.rounded(.down) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.currentTime = $0 }
            .store(in: &cancellables)

        engine.durationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.duration = $0 }
            .store(in: &cancellables)

        engine.sourcePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                guard let self, let source else { return }
                self.title = source.title
                self.subtitle = source.subtitle
                self.artworkName = source.artworkName
                self.isLive = source.isLive
                self.isPresented = true
                self.syncSelection(with: source)
            }
            .store(in: &cancellables)
    }

    /// When playback is started elsewhere (CarPlay), adopt it as this view model's selection.
    private func syncSelection(with source: PlaybackSource) {
        switch source {
        case .radio(let url):
            if case .radio = mode { return }
            onlineStream = url
            podcastId = nil
            podcast = nil
            isDownloaded = false
        case .podcast(let playing):
            if let podcastId, podcastId == playing.id { return }
            self.podcastId = playing.id
            self.podcast = loadPodcastFromRealm(with: playing.id) ?? playing
            self.onlineStream = nil
            self.isDownloaded = self.podcast?.isDownloaded ?? false
            self.showDeleteButton = self.isDownloaded
        }
    }

    // MARK: - Mode

    private func applyMode() {
        switch mode {
        case .radio(let stream):
            onlineStream = stream ?? AppConstants.fallbackStreamURL
            podcastId = nil
            podcast = nil
            title = "Radio uživo"
            subtitle = "Daško i Mlađa"
            artworkName = "img_radio"
            isLive = true
            isDownloaded = false
            showDeleteButton = false

        case .podcast(let selected):
            onlineStream = nil
            podcastId = selected.id
            podcast = loadPodcastFromRealm(with: selected.id) ?? selected
            title = selected.title
            subtitle = selected.subtitle
            artworkName = selected.show.imageName
            isLive = false
            isDownloaded = podcast?.isDownloaded ?? false
            showDeleteButton = isDownloaded

        case .none:
            onlineStream = nil
            podcastId = nil
            podcast = nil
            title = ""
            subtitle = ""
            isLive = false
            isDownloaded = false
            showDeleteButton = false
        }

        progress = 0
        isDownloading = false
        showCheckmark = false
    }

    private var currentSource: PlaybackSource? {
        switch mode {
        case .radio:
            guard let url = onlineStream ?? AppConstants.fallbackStreamURL else { return nil }
            return .radio(url: url)
        case .podcast:
            guard let podcast else { return nil }
            return .podcast(podcast)
        case .none:
            return nil
        }
    }

    // MARK: - Transport

    func togglePlayPause() {
        guard let source = currentSource else { return }

        if engine.source == source {
            engine.toggle()
        } else {
            engine.play(source)
        }
        isPresented = true
    }

    func seek(to time: TimeInterval) { engine.seek(to: time) }
    func skipForward() { engine.skip(by: 15) }
    func skipBackward() { engine.skip(by: -15) }

    /// Stops playback and dismisses the mini player. Previously this only hid the bar.
    func stop() {
        engine.stop()
        isPresented = false
        isExpanded = false
        mode = nil
    }

    func toggleDeleteButton() {
        showDeleteButton = podcast?.isDownloaded ?? false
    }

    // MARK: - Download

    func downloadPodcast() {
        guard let urlString = podcast?.podcastUrl, let podcastUrl = URL(string: urlString) else { return }

        isDownloading = true
        showCheckmark = false

        podcastService.downloadPodcasts(from: podcastUrl, completion: { [weak self] result in
            guard let self else { return }
            self.isDownloading = false

            switch result {
            case .success(let location):
                self.isDownloaded = true
                self.podcast?.fileUrl = location.lastPathComponent
                if let podcast = self.podcast {
                    self.savePodcastToRealm(PodcastRealm(from: podcast))
                    // If this episode is the one playing, continue from the local file.
                    if self.engine.source == .podcast(podcast) || self.podcastId == podcast.id {
                        self.engine.switchToLocalFile(location)
                    }
                }
                self.showCheckmark = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.showCheckmark = false
                    self?.showDeleteButton = true
                }

            case .failure(let error):
                debugPrint("Error downloading file: \(error.localizedDescription)")
            }
        }, progressHandler: { [weak self] progress in
            self?.progress = progress
        })
    }

    func deletePodcast() {
        guard let podcast, let fileName = podcast.fileUrl else { return }

        switch fileService.deleteFile(with: fileName) {
        case .success:
            isDownloaded = false
            showDeleteButton = false
            self.podcast?.fileUrl = nil
            if let updated = self.podcast {
                savePodcastToRealm(PodcastRealm(from: updated))
            }
        case .failure(let error):
            debugPrint("Error deleting file: \(error.localizedDescription)")
        }
    }

    // MARK: - Realm

    private func loadPodcastFromRealm(with id: UUID) -> Podcast? {
        guard let realm,
              let podcastRealm = realm.objects(PodcastRealm.self)
                .filter("id == %@", id.uuidString).first else {
            debugPrint("Podcast \(id) not found in Realm")
            return nil
        }
        return Podcast(from: podcastRealm)
    }

    private func savePodcastToRealm(_ newPodcast: PodcastRealm) {
        guard let realm else { return }
        do {
            try realm.write {
                realm.add(newPodcast, update: .modified)
            }
        } catch {
            debugPrint("Error saving podcast to Realm: \(error.localizedDescription)")
        }
    }
}
