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
    /// Download progress, 0...1 - not the playback position, which is `playbackProgress`.
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

    private let engine: PlaybackEngineType
    /// Read for what to reopen, and cleared when the player is closed.
    /// Written only by ListeningRecorder.
    private let playbackState: PlaybackStateStore
    /// Where the stored copy of an episode comes from - the one that knows
    /// about favourites, downloads and how far it has been listened to.
    private let episodes: EpisodeLookup
    /// Where a restored episode should start. Cleared the moment it is used,
    /// so it can never send a later press back in time.
    private var restoredPosition: TimeInterval?
    private var cancellables = Set<AnyCancellable>()

    private var podcastId: UUID?
    private var podcast: Podcast?
    private var onlineStream: URL?

    // MARK: - Init

    init(mode: PlayerMode? = nil,
         engine: PlaybackEngineType = PlaybackEngine.shared,
         playbackState: PlaybackStateStore = .shared,
         episodes: EpisodeLookup = PodcastRepository.shared,
         storeChanges: AnyPublisher<Void, Never> = AppDatabase.shared.didChangeRemotely) {
        self.engine = engine
        self.playbackState = playbackState
        self.episodes = episodes
        self.mode = mode

        bindEngine()
        if mode != nil { applyMode() }

        // Something arrived from another device. While nothing plays here,
        // the player follows the account.
        storeChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.catchUpIfIdle() }
            .store(in: &cancellables)
    }

    /// Keeps the view model in step with whatever the engine is doing - including
    /// playback started from CarPlay or the lock screen.
    private func bindEngine() {
        engine.isPlayingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                guard let self else { return }
                self.isPlaying = playing
            }
            .store(in: &cancellables)

        engine.isBufferingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isBuffering = $0 }
            .store(in: &cancellables)

        // Rounded and de-duplicated: the engine ticks twice a second, and every
        // distinct value re-renders each view observing this object.
        // Both of these ignore the engine while it holds nothing. Subscribing
        // hands over the current value at once - zero, at launch - and
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

        // The lists can change the episode that is loaded here - favouriting
        // from a row should move the heart on the player too, and deleting a
        // download should drop the delete button.
        EpisodeLibrary.shared.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self,
                      let podcastId = self.podcastId,
                      let refreshed = self.storedPodcast(with: podcastId) else { return }
                self.podcast = refreshed
                self.isFavorite = refreshed.isFavorite
                self.isDownloaded = refreshed.isDownloaded
                self.showDeleteButton = refreshed.isDownloaded
                self.isDownloading = EpisodeLibrary.shared.isDownloading(refreshed)
                self.adoptSyncedPosition(from: refreshed)
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
            self.podcast = storedPodcast(with: playing.id) ?? playing
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
        let carriesOn = engineIsAlreadyOn(mode)

        if !carriesOn {
            // The episode being left is written down by ListeningRecorder,
            // when the engine actually moves on - not here, where it may only
            // have been on screen.
            currentTime = 0
        }

        switch mode {
        case .radio(let stream):
            onlineStream = stream ?? AppConstants.fallbackStreamURL
            podcastId = nil
            podcast = nil
            title = String(localized: "Radio uživo")
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
            podcast = storedPodcast(with: selected.id) ?? selected
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

            // Opened where it was left. Only on a swap: the same episode
            // selected again while it plays would otherwise be dragged back to
            // whatever was last written down, which is a position from before
            // the last few minutes of listening.
            if !carriesOn, let resume = podcast?.resumePosition {
                restoredPosition = resume
                currentTime = resume
            }

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
    /// without the audio changing - a favourite, a download, how far it has
    /// been listened to - is ignored.
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
        // The freshest thing known about this episode, asked for at the last
        // possible moment. An import from another device can land seconds
        // after launch - well after the player restored - and this is the
        // press that decides where the audio actually starts.
        refreshFromStoreIfIdle()

        guard let source = currentSource else { return }

        // Before the engine is touched. Building a player and claiming the
        // audio session both block, and for a streamed episode that is long
        // enough to see: the bar used to appear when the file opened rather
        // than when it was asked for.
        isPresented = true

        guard !source.isSameContent(as: engine.source) else {
            engine.toggle()
            restoredPosition = nil
            return
        }

        // A restored episode has never been loaded into the engine, so the
        // first press is what actually opens it - at the second it was left
        // on, not at the beginning.
        let position = restoredPosition
        restoredPosition = nil

        // A runloop later, so the bar is on screen before any of that
        // blocking happens. Everything the screens read - the title, the
        // artwork, the position - is already set.
        DispatchQueue.main.async { [engine] in
            engine.play(source, startingAt: position)
        }
    }

    /// What tapping a row means. The episode that is playing takes you to the
    /// player; anything else starts. A row is not a pause button - the same
    /// rule the car list follows, for the same reason: tapping the thing that
    /// is already playing has never meant "stop it".
    func open(_ podcast: Podcast) {
        if case .podcast(let playing) = engine.source, playing.id == podcast.id {
            isPresented = true
            isExpanded = true
            return
        }

        mode = .podcast(podcast: podcast)
        togglePlayPause()
    }

    /// What the play button on a row means, which is the one place a list is
    /// allowed to stop something: it is a transport control, and it looks like
    /// one.
    func toggle(_ podcast: Podcast) {
        mode = .podcast(podcast: podcast)
        togglePlayPause()
    }

    /// What a tap on a row means, which is not the same thing on every screen.
    ///
    /// On a phone the row is the only way in, so it opens the player. Where the
    /// row draws its own play state, the row *is* the transport control: a tap
    /// starts or stops it and nothing is thrown over the list, because the
    /// glyph that said "playing" would otherwise be hidden by the screen the
    /// tap just opened.
    func activate(_ podcast: Podcast, expandingPlayer: Bool) {
        if expandingPlayer {
            open(podcast)
        } else {
            toggle(podcast)
        }
    }

    /// True while this is the episode the engine holds.
    func isCurrent(_ podcast: Podcast) -> Bool {
        if case .podcast(let playing) = engine.source { return playing.id == podcast.id }
        return false
    }

    /// Opens an episode at a given second - what tapping a bookmark does.
    func play(_ podcast: Podcast, startingAt position: TimeInterval) {
        mode = .podcast(podcast: podcast)
        guard let source = currentSource else { return }
        // A bookmark supersedes whatever was restored: this is the position
        // being asked for now.
        restoredPosition = nil
        // Shown straight away rather than after the seek lands, so the
        // scrubber never blinks through zero on the way to the bookmark.
        currentTime = max(0, position)
        isPresented = true
        // A runloop later, for the reason in togglePlayPause: opening a file
        // blocks, and the bar should be there before it does.
        DispatchQueue.main.async { [engine] in
            engine.play(source, startingAt: position)
        }
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

    /// Puts the player back the way it was found, without making a sound and
    /// without touching the network. Nothing is loaded into the engine: the
    /// mini player reads from here, and the first press is what opens the
    /// audio - at the right second, because of `restoredPosition`.
    func restorePlaybackState() {
        guard mode == nil, engine.source == nil else { return }

        // The account's last listen, when it is a different episode and
        // later than anything this device has to say. The player comes back
        // to what was listened to last, not to what was listened to last here.
        if let fromAccount = newerListenFromAccount(),
           fromAccount.id != playbackState.saved?.podcastId {
            #if DEBUG
            AppLog.write(.player, "restoring from the account: \(fromAccount.title) at \(Int(fromAccount.playedPosition))s")
            #endif
            showIdle(fromAccount, at: fromAccount.resumePosition ?? 0)
            return
        }

        guard let saved = playbackState.saved,
              let podcast = episodes.podcast(with: saved.podcastId) else { return }

        // Heard through to the end somewhere else since this device last
        // touched it. There is nothing to come back to, and reopening at this
        // device's old position - minutes before the end of something already
        // finished - is the wrong answer twice over.
        if finishedElsewhere(podcast) {
            playbackState.clear()
            return
        }

        // Two records of the same listening, and the later one is right.
        //
        // This slot is written on this device only; the episode's own record
        // syncs. Before it did, the slot was always the newer of the two and
        // taking it blindly was correct. Now an episode carried on elsewhere
        // comes back with a later date, and the phone that stopped at
        // fifty-two minutes has to yield to the Mac that got to an hour and
        // a half - otherwise it reopens at its own position and the sync
        // looks broken when it worked.
        let position: TimeInterval
        if let syncedAt = podcast.playedAt, syncedAt > saved.savedAt,
           let synced = podcast.resumePosition {
            position = synced
        } else {
            position = saved.position
        }

        #if DEBUG
        AppLog.write(.player, "restoring \(Int(position))s for \(saved.podcastId) - slot \(Int(saved.position))s at \(saved.savedAt), synced \(Int(podcast.playedPosition))s at \(String(describing: podcast.playedAt))")
        #endif

        showIdle(podcast, at: position)
    }

    /// An episode in the player, not playing, ready to start at `position` on
    /// the first press.
    private func showIdle(_ podcast: Podcast, at position: TimeInterval) {
        mode = .podcast(podcast: podcast)
        restoredPosition = position
        currentTime = position
        // The feed already told us how long it runs, so the scrubber and the
        // mini player's bar can show the right place before anything is
        // loaded. The engine replaces this with the file's own duration the
        // moment it opens it.
        duration = podcast.durationInSeconds
        isPresented = true
    }

    /// The newest unfinished listen on the account, if it is newer than
    /// everything this device has said: its own slot, and the last time the
    /// player here was closed.
    private func newerListenFromAccount() -> Podcast? {
        guard let latest = episodes.lastListened(), let listenedAt = latest.playedAt else { return nil }
        return listenedAt > lastSaidHere ? latest : nil
    }

    /// The last time this device said anything about what to come back to:
    /// a listen written down here, or the player being closed.
    private var lastSaidHere: Date {
        max(playbackState.saved?.savedAt ?? .distantPast, playbackState.clearedAt ?? .distantPast)
    }

    /// Nothing is playing here. Paused counts: a paused player is holding a
    /// place, not listening, and a later listen on another device is newer
    /// than anything it has to say. It used to take "nothing loaded at all",
    /// and a phone paused a few minutes from the end went on showing those
    /// minutes while the Mac played them.
    private var isIdle: Bool { !isPlaying && !isBuffering }

    /// Whether the engine holds this episode - loaded, playing or paused.
    private func engineHolds(_ id: UUID?) -> Bool {
        guard let id, case .podcast(let loaded) = engine.source else { return false }
        return loaded.id == id
    }

    /// Played to the end on another device, after this one last said
    /// anything. By position rather than by the finished flag, which is
    /// sticky: an episode heard once and started again elsewhere keeps the
    /// flag, and that is not the same as having been finished just now.
    private func finishedElsewhere(_ podcast: Podcast) -> Bool {
        guard podcast.hasReachedEnd, let at = podcast.playedAt else { return false }
        return at > lastSaidHere
    }

    /// Coming back to the app, or hearing that something arrived: while
    /// nothing is playing here, show what the account listened to last, then
    /// bring its position up to date.
    ///
    /// Not part of pressing play. A press is about the episode on screen, and
    /// swapping it for another in the instant before it starts would play
    /// something nobody chose.
    func catchUpIfIdle() {
        followAccountIfIdle()
        refreshFromStoreIfIdle()
        putAwayIfFinishedElsewhere()
    }

    private func followAccountIfIdle() {
        guard isIdle else { return }
        if case .radio = mode { return }
        guard let fromAccount = newerListenFromAccount(), fromAccount.id != podcastId else { return }

        #if DEBUG
        AppLog.write(.player, "following the account: \(fromAccount.title) at \(Int(fromAccount.playedPosition))s")
        #endif
        // A paused episode still loaded here is let go first, so the lock
        // screen does not go on offering the one that was left. What it got
        // to is already written down, and letting go does not write it again.
        if engine.source != nil { engine.stop() }
        showIdle(fromAccount, at: fromAccount.resumePosition ?? 0)
    }

    /// The episode on screen was finished on another device, and there is
    /// nothing newer to show instead: the player goes away, as it would have
    /// here. Not on a press of play - see togglePlayPause.
    private func putAwayIfFinishedElsewhere() {
        guard isIdle, !isLive, let podcast, finishedElsewhere(podcast) else { return }

        #if DEBUG
        AppLog.write(.player, "finished elsewhere, putting the player away: \(podcast.title)")
        #endif
        stop()
    }

    /// Re-reads this episode from the store while nothing plays here, in case
    /// something arrived from another device since it was last read. Doing it
    /// on demand rather than only on notification means syncing does not
    /// depend on a notification arriving.
    func refreshFromStoreIfIdle() {
        guard isIdle, !isLive, let podcastId else { return }

        // Not just re-read: read again from a store that has been asked to
        // forget what it already showed us.
        episodes.refreshFromStore()

        #if DEBUG
        (episodes as? PodcastRepository)?.describeState(for: podcastId)
        #endif

        guard let stored = episodes.podcast(with: podcastId) else { return }

        podcast = stored
        isFavorite = stored.isFavorite
        isDownloaded = stored.isDownloaded
        showDeleteButton = stored.isDownloaded
        adoptSyncedPosition(from: stored)
    }

    /// A position that arrived from another device while this one was already
    /// open. The import can land seconds after launch, well after the player
    /// has restored, and without this the bar sits at the old position until
    /// the next launch - by which time the same thing happens again.
    ///
    /// Only while nothing plays here; a playing device's own clock is the
    /// truth. Paused is fine: if the episode is loaded, the engine is moved
    /// to the new place, since a press of play resumes the engine where it
    /// stands and would ignore anything written only on screen.
    private func adoptSyncedPosition(from podcast: Podcast) {
        guard isIdle, !isLive else { return }
        guard let syncedAt = podcast.playedAt, syncedAt > lastSaidHere else { return }
        guard let synced = podcast.resumePosition else { return }
        guard abs(synced - currentTime) > 1 else { return }

        if engineHolds(podcast.id) {
            engine.seek(to: synced)
            restoredPosition = nil
        } else {
            restoredPosition = synced
            duration = podcast.durationInSeconds
        }
        currentTime = synced
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
        self.podcast = storedPodcast(with: podcast.id) ?? podcast
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
        // rule refused - the one case where nothing ever completes.
        showCheckmark = false
        progress = 0

        // One download path for the whole app - the row's Preuzmi and this
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

    // MARK: - The store

    /// Reads go through the repository like everywhere else; writes are the
    /// library's job, so this view model no longer touches the store directly.
    private func storedPodcast(with id: UUID) -> Podcast? {
        guard let podcast = episodes.podcast(with: id) else {
            AppLog.write(.player, "Podcast \(id) not found in the store")
            return nil
        }
        return podcast
    }

}
