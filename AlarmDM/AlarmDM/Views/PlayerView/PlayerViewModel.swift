//
//  PlayerViewModel.swift
//  AlarmDM
//
//  A thin, observable façade over PlaybackEngine.shared. It owns the UI-only
//  concerns (presentation, download progress) and mirrors
//  playback state from the engine, so the phone UI and the CarPlay scene can
//  never disagree about what is playing.
//

import Foundation
import Combine
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
    /// The engine holds nothing until the first press on a restored episode,
    /// so the bar reads from what was restored instead of showing zero for
    /// something that is plainly half finished.
    var playbackProgress: Double {
        guard engine.hasContent else {
            guard duration > 0 else { return 0 }
            return min(max(currentTime / duration, 0), 1)
        }
        return engine.progress
    }

    // MARK: - Download state

    @Published var isDownloaded: Bool = false
    @Published private(set) var isFavorite: Bool = false
    /// The song the station is announcing, during live radio only.
    @Published private(set) var liveTrack: LiveTrack?
    /// Briefly true after a bookmark is captured, so the button can say it
    /// happened without a dialog interrupting playback.
    @Published private(set) var justBookmarked = false
    @Published var isDownloading: Bool = false
    /// Download progress, 0...1 — not the playback position, which is `playbackProgress`.
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
    private let playbackState: PlaybackStateStore
    /// Where a restored episode should start. Cleared the moment it is used,
    /// so it can never send a later press back in time.
    private var restoredPosition: TimeInterval?
    private var cancellables = Set<AnyCancellable>()

    private var podcastId: UUID?
    private var podcast: Podcast?
    private var onlineStream: URL?

    // MARK: - Init

    init(mode: PlayerMode? = nil,
         engine: PlaybackEngine = .shared,
         playbackState: PlaybackStateStore = .shared) {
        self.engine = engine
        self.playbackState = playbackState
        self.mode = mode

        bindEngine()
        if mode != nil { applyMode() }
    }

    /// Keeps the view model in step with whatever the engine is doing — including
    /// playback started from CarPlay or the lock screen.
    private func bindEngine() {
        engine.isPlayingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                guard let self else { return }
                self.isPlaying = playing
                if !playing { self.rememberPlaybackPosition() }
            }
            .store(in: &cancellables)

        engine.isBufferingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isBuffering = $0 }
            .store(in: &cancellables)

        // Rounded and de-duplicated: the engine ticks twice a second, and every
        // distinct value re-renders each view observing this object.
        // Both of these ignore the engine while it holds nothing. Subscribing
        // hands over the current value at once — zero, at launch — and
        // receive(on:) delivers it a runloop later, which lands after the
        // restore has already put the saved time and duration here. Without
        // the guard, coming back to a half finished episode showed 00:00.
        engine.currentTimePublisher
            .map { $0.rounded(.down) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self, self.engine.hasContent else { return }
                self.currentTime = time
            }
            .store(in: &cancellables)

        engine.durationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                guard let self, self.engine.hasContent else { return }
                // A freshly created item reports zero until the file has
                // loaded. Taking that at face value collapses the scrubber's
                // range to nothing and flings the handle to the far end, until
                // the real duration arrives a moment later. The feed already
                // said how long the episode runs, so keep that instead.
                guard duration > 0 else { return }
                self.duration = duration
            }
            .store(in: &cancellables)

        engine.liveTrackPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.liveTrack = $0 }
            .store(in: &cancellables)

        EpisodeLibrary.shared.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self, update.id == self.podcastId else { return }
                self.progress = update.progress
            }
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

        // The lists can change the episode that is loaded here — favouriting
        // from a row should move the heart on the player too, and deleting a
        // download should drop the delete button.
        EpisodeLibrary.shared.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self,
                      let podcastId = self.podcastId,
                      let refreshed = self.loadPodcastFromRealm(with: podcastId) else { return }
                self.podcast = refreshed
                self.isFavorite = refreshed.isFavorite
                self.isDownloaded = refreshed.isDownloaded
                self.showDeleteButton = refreshed.isDownloaded
                self.isDownloading = EpisodeLibrary.shared.isDownloading(refreshed)
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
            self.isFavorite = self.podcast?.isFavorite ?? false
            self.showDeleteButton = self.isDownloaded
        }
    }

    // MARK: - Mode

    private func applyMode() {
        // A different thing is being loaded, so the old position is not a
        // position any more. Without this the scrubber shows where the
        // previous episode stopped until the engine's first zero arrives,
        // which it does a runloop late.
        //
        // Only when the audio actually changes, though. Compared by identity
        // and not by value: an episode re-selected from a refreshed row is a
        // different Podcast carrying the same audio, and sending the scrubber
        // to zero under playback that never stopped would be the worse bug of
        // the two.
        if !engineIsAlreadyOn(mode) {
            currentTime = 0
        }

        switch mode {
        case .radio(let stream):
            onlineStream = stream ?? AppConstants.fallbackStreamURL
            podcastId = nil
            podcast = nil
            title = "Radio uživo"
            subtitle = "Daško i Mlađa"
            artworkName = "img_radio"
            isLive = true
            duration = 0
            isDownloaded = false
            isFavorite = false
            showDeleteButton = false

        case .podcast(let selected):
            onlineStream = nil
            podcastId = selected.id
            podcast = loadPodcastFromRealm(with: selected.id) ?? selected
            title = selected.title
            subtitle = selected.subtitle
            artworkName = selected.show.imageName
            isLive = false
            // Known before a single byte is fetched, which is what keeps the
            // scrubber sane between pressing play and the file opening.
            duration = podcast?.durationInSeconds ?? 0
            isDownloaded = podcast?.isDownloaded ?? false
            isFavorite = podcast?.isFavorite ?? false
            showDeleteButton = isDownloaded

        case .none:
            onlineStream = nil
            podcastId = nil
            podcast = nil
            title = ""
            subtitle = ""
            isLive = false
            isDownloaded = false
            isFavorite = false
            showDeleteButton = false
        }

        // Adopt whatever the library is already doing for this episode, so
        // opening the player mid-download shows the ring instead of an idle
        // download button.
        if let podcast {
            isDownloading = EpisodeLibrary.shared.isDownloading(podcast)
            progress = EpisodeLibrary.shared.progress(for: podcast.id)
        } else {
            isDownloading = false
            progress = 0
        }
        showCheckmark = false
    }

    /// Whether the engine is already playing what this mode points at. By
    /// episode id and by kind, so everything about a row that can change
    /// without the audio changing — a favourite, a download, how far it has
    /// been listened to — is ignored.
    private func engineIsAlreadyOn(_ mode: PlayerMode?) -> Bool {
        guard let mode, let loaded = engine.source else { return false }

        switch (mode, loaded) {
        case (.radio, .radio):
            return true
        case (.podcast(let selected), .podcast(let playing)):
            return selected.id == playing.id
        default:
            return false
        }
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
            // A restored episode has never been loaded into the engine, so the
            // first press is what actually opens it — at the second it was
            // left on, not at the beginning.
            engine.play(source, startingAt: restoredPosition)
        }
        restoredPosition = nil
        isPresented = true
    }

    /// Opens an episode at a given second — what tapping a bookmark does.
    func play(_ podcast: Podcast, startingAt position: TimeInterval) {
        mode = .podcast(podcast: podcast)
        guard let source = currentSource else { return }
        // A bookmark supersedes whatever was restored: this is the position
        // being asked for now.
        restoredPosition = nil
        // Shown straight away rather than after the seek lands, so the
        // scrubber never blinks through zero on the way to the bookmark.
        currentTime = max(0, position)
        engine.play(source, startingAt: position)
        isPresented = true
    }

    func seek(to time: TimeInterval) {
        // A restored episode has nothing loaded yet, and the engine refuses to
        // seek a player it does not have. Move the mark the first press will
        // start from instead, so dragging works before a note is played.
        guard engine.hasContent else {
            restoredPosition = max(0, time)
            currentTime = max(0, time)
            return
        }
        engine.seek(to: time)
    }
    func skipForward() { engine.skip(by: 15) }
    func skipBackward() { engine.skip(by: -15) }

    /// Stops playback and dismisses the mini player. Previously this only hid the bar.
    func stop() {
        engine.stop()
        isPresented = false
        isExpanded = false
        mode = nil
        restoredPosition = nil
        // Closing the bar is the one clear statement that there is nothing to
        // come back to.
        playbackState.clear()
    }

    // MARK: - Carrying on where it was left

    /// Writes down what is playing and where. Called when playback pauses and
    /// when the app goes away — not on a timer, because a second's accuracy
    /// costs a write every second for the rest of the episode.
    func rememberPlaybackPosition() {
        guard !isLive, let podcastId, currentTime > 0 else { return }
        playbackState.save(PlaybackState(podcastId: podcastId, position: currentTime))

        // Two different things, saved in two different places. The line above
        // is the player's own state — one slot, what to reopen on launch. This
        // one is the library's record of this particular episode, which every
        // episode has and which is what will sync between devices.
        let end = podcast?.endOfShow ?? 0
        EpisodeLibrary.shared.recordProgress(
            position: currentTime,
            hasFinished: end > 0 && currentTime >= end,
            for: podcastId
        )
    }

    /// Puts the player back the way it was found, without making a sound and
    /// without touching the network. Nothing is loaded into the engine: the
    /// mini player reads from here, and the first press is what opens the
    /// audio — at the right second, because of `restoredPosition`.
    func restorePlaybackState() {
        guard mode == nil, engine.source == nil else { return }
        guard let saved = playbackState.saved,
              let podcast = PodcastRepository.shared.podcast(with: saved.podcastId) else { return }

        restoredPosition = saved.position
        mode = .podcast(podcast: podcast)
        currentTime = saved.position
        // The feed already told us how long it runs, so the scrubber and the
        // mini player's bar can show the right place before anything is
        // loaded. The engine replaces this with the file's own duration the
        // moment it opens it.
        duration = podcast.durationInSeconds
        isPresented = true
    }

    func addBookmark() {
        guard BookmarkLibrary.shared.capture() != nil else { return }
        justBookmarked = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.justBookmarked = false
        }
    }

    func toggleFavourite() {
        guard let podcast else { return }
        EpisodeLibrary.shared.toggleFavourite(podcast)
        self.podcast = loadPodcastFromRealm(with: podcast.id) ?? podcast
        isFavorite = self.podcast?.isFavorite ?? false
    }

    func toggleDeleteButton() {
        showDeleteButton = podcast?.isDownloaded ?? false
    }

    // MARK: - Download

    func downloadPodcast() {
        guard let podcast, !podcast.isDownloaded else { return }

        // `isDownloading` is not set here: the library decides whether the
        // download actually starts, and says so through `didChange`. Setting it
        // optimistically left the ring spinning forever whenever the WiFi-only
        // rule refused — the one case where nothing ever completes.
        showCheckmark = false
        progress = 0

        // One download path for the whole app — the row's Preuzmi and this
        // button run the same code, so they cannot drift apart or fight over
        // the same episode. The library refreshes `isDownloaded` and the
        // delete button through `didChange`.
        EpisodeLibrary.shared.download(podcast) { [weak self] result in
            guard let self else { return }

            guard case .success(let location) = result else { return }

            // If this episode is the one playing, continue from the local file.
            if self.podcastId == podcast.id {
                self.engine.switchToLocalFile(location)
            }

            self.showCheckmark = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.showCheckmark = false
            }
        }
    }

    func deletePodcast() {
        guard let podcast else { return }
        EpisodeLibrary.shared.deleteDownload(podcast)
    }

    // MARK: - Realm

    /// Reads go through the repository like everywhere else; writes are the
    /// library's job, so this view model no longer touches Realm directly.
    private func loadPodcastFromRealm(with id: UUID) -> Podcast? {
        guard let podcast = PodcastRepository.shared.podcast(with: id) else {
            debugPrint("Podcast \(id) not found in Realm")
            return nil
        }
        return podcast
    }

}
