//
//  PlaybackEngine.swift
//  AlarmDM
//
//  Single source of truth for audio playback.
//
//  Both the SwiftUI app and the CarPlay scene drive this one object, so the
//  phone and the car always show the same thing and only one AVPlayer ever
//  exists. Owns the audio session, the Now Playing info and the remote
//  command centre.
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit

// MARK: - What is playing

enum PlaybackSource: Equatable {
    case radio(url: URL)
    case podcast(Podcast)

    /// What is playing, rather than what is known about it.
    ///
    /// Two of these can hold the same audio and still be unequal: a Podcast
    /// carries a favourite flag, a downloaded file and how far it has been
    /// listened to, and every one of those changes while the episode plays.
    /// Comparing the whole value to decide whether something is already
    /// loaded answers "no" the moment any of it is written down — and the
    /// answer to that question decides between carrying on and starting the
    /// file again from the beginning.
    var contentId: String {
        switch self {
        case .radio(let url): return url.absoluteString
        case .podcast(let podcast): return podcast.id.uuidString
        }
    }

    func isSameContent(as other: PlaybackSource?) -> Bool {
        guard let other else { return false }
        return contentId == other.contentId
    }

    var title: String {
        switch self {
        case .radio: return "Radio uživo"
        case .podcast(let podcast): return podcast.title
        }
    }

    var subtitle: String {
        switch self {
        case .radio: return "Daško i Mlađa"
        case .podcast(let podcast):
            return podcast.subtitle.isEmpty ? podcast.show.displayName : podcast.subtitle
        }
    }

    var artworkName: String {
        switch self {
        case .radio: return "img_radio"
        case .podcast(let podcast): return podcast.show.imageName
        }
    }

    var isLive: Bool {
        if case .radio = self { return true }
        return false
    }

    var podcast: Podcast? {
        if case .podcast(let podcast) = self { return podcast }
        return nil
    }
}

// MARK: - What the station says is playing

/// A track announced by the stream itself. Shoutcast/Icecast send one string,
/// almost always "Artist - Title", and HLS streams send the same thing as timed
/// metadata — so one parser covers both.
struct LiveTrack: Equatable {
    let artist: String?
    let title: String

    var display: String {
        guard let artist, !artist.isEmpty else { return title }
        return "\(artist) – \(title)"
    }

    /// Returns nil for anything that is not worth showing: empty strings, a URL
    /// (some encoders send the stream address), or the station name on its own,
    /// which says nothing the screen is not already saying.
    init?(raw: String) {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count < 200 else { return nil }
        guard !cleaned.lowercased().hasPrefix("http") else { return nil }

        let stationNames = ["daskoimladja", "dasko i mladja", "daško i mlađa", "radio"]
        if stationNames.contains(cleaned.lowercased()) { return nil }

        if let separator = cleaned.range(of: " - ") ?? cleaned.range(of: " – ") {
            let artist = String(cleaned[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            let title = String(cleaned[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !artist.isEmpty && !title.isEmpty {
                self.artist = artist
                self.title = title
                return
            }
        }

        self.artist = nil
        self.title = cleaned
    }
}

// MARK: - Engine

/// What the player screens actually need from the engine. It exists so the
/// view model can be driven by something that is not an AVPlayer: every rule
/// about swapping episodes, keeping positions and restoring state is decided
/// in the view model, and testing it against the real engine would mean
/// testing AVFoundation as well.
///
/// The engine itself is unchanged by this — it is the only thing that
/// implements it, and it implements it by already having these members.
protocol PlaybackEngineType: AnyObject {
    var source: PlaybackSource? { get }
    var hasContent: Bool { get }
    var isLive: Bool { get }
    var progress: Double { get }

    var sourcePublisher: AnyPublisher<PlaybackSource?, Never> { get }
    var isPlayingPublisher: AnyPublisher<Bool, Never> { get }
    var isBufferingPublisher: AnyPublisher<Bool, Never> { get }
    var currentTimePublisher: AnyPublisher<TimeInterval, Never> { get }
    var durationPublisher: AnyPublisher<TimeInterval, Never> { get }
    var liveTrackPublisher: AnyPublisher<LiveTrack?, Never> { get }

    func play(_ source: PlaybackSource, startingAt position: TimeInterval?)
    func toggle()
    func stop()
    func seek(to time: TimeInterval, completion: (() -> Void)?)
    func skip(by seconds: TimeInterval)
    func switchToLocalFile(_ fileURL: URL)
}

extension PlaybackEngineType {
    /// Most callers only want to move; a protocol requirement cannot carry a
    /// default argument, so the short form lives here.
    func seek(to time: TimeInterval) {
        seek(to: time, completion: nil)
    }
}

final class PlaybackEngine: NSObject, ObservableObject, PlaybackEngineType {

    static let shared = PlaybackEngine()

    // MARK: Published state

    @Published private(set) var source: PlaybackSource?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var lastErrorMessage: String?
    /// Only ever set during live radio, and only when the stream announces it.
    @Published private(set) var liveTrack: LiveTrack?

    // Publishers exposed explicitly: the stored properties are private(set), so
    // consumers observe through these instead of the synthesised $ projections.
    var sourcePublisher: AnyPublisher<PlaybackSource?, Never> { $source.eraseToAnyPublisher() }
    var isPlayingPublisher: AnyPublisher<Bool, Never> { $isPlaying.eraseToAnyPublisher() }
    var isBufferingPublisher: AnyPublisher<Bool, Never> { $isBuffering.eraseToAnyPublisher() }
    var currentTimePublisher: AnyPublisher<TimeInterval, Never> { $currentTime.eraseToAnyPublisher() }
    var durationPublisher: AnyPublisher<TimeInterval, Never> { $duration.eraseToAnyPublisher() }
    var liveTrackPublisher: AnyPublisher<LiveTrack?, Never> { $liveTrack.eraseToAnyPublisher() }

    var hasContent: Bool { source != nil }
    var isLive: Bool { source?.isLive ?? false }

    var progress: Double {
        guard duration > 0, duration.isFinite else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    // MARK: Private state

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    /// Where to jump once the new item is ready. Seeking a stream that has not
    /// finished loading is quietly dropped, so the request waits here instead.
    private var pendingSeek: TimeInterval?
    /// Whether to start playing once that jump has landed. An episode opened
    /// at a position must not be heard from the beginning first, even for the
    /// half second it takes the seek to arrive.
    private var playAfterPendingSeek = false
    /// Raised while a seek is in flight. The periodic observer keeps reporting
    /// the old position until the seek lands, and letting that through drags
    /// the slider back to where it was before the gesture.
    private var isSeeking = false
    /// Distinguishes a seek that finished from one a newer seek replaced, so
    /// the older one cannot declare the newer one over.
    private var seekGeneration = 0
    private var metadataOutput: AVPlayerItemMetadataOutput?
    #if DEBUG
    private var lastBufferLog: Date = .distantPast
    #endif
    private var commandsConfigured = false
    private let fileService: FileServiceProtocol

    private init(fileService: FileServiceProtocol = FileService()) {
        self.fileService = fileService
        super.init()
        configureAudioSession()
        observeInterruptions()
        configureRemoteCommands()
    }

    // MARK: - Public API

    /// Starts playback of `source`. Re-selecting what is already loaded just resumes.
    func play(_ source: PlaybackSource, startingAt position: TimeInterval? = nil) {
        if source.isSameContent(as: self.source), player != nil {
            if let position { seek(to: position) }
            resume()
            return
        }

        pendingSeek = position
        playAfterPendingSeek = position != nil

        guard let url = resolveURL(for: source) else {
            lastErrorMessage = "Nije moguće pronaći audio za \(source.title)."
            return
        }

        teardownPlayer()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true

        self.player = player
        self.source = source
        self.currentTime = 0
        self.duration = 0
        self.lastErrorMessage = nil
        self.liveTrack = nil

        attachObservers(to: player, item: item)
        activateSession()
        player.play()
        updateNowPlayingInfo()
    }

    func toggle() {
        guard player != nil else {
            if let source { play(source) }
            return
        }
        isPlaying ? pause() : resume()
    }

    func pause() {
        player?.pause()
        updateNowPlayingPlaybackState()
    }

    func resume() {
        // Another app taking the audio session can leave the item failed, and a
        // failed item cannot be told to carry on — there is nothing to carry on
        // with. It has to be built again, at the second it stopped on.
        let isBroken = player == nil || player?.currentItem?.status == .failed

        guard !isBroken else {
            guard let source else { return }
            let resumeAt = source.isLive ? nil : currentTime
            play(source, startingAt: resumeAt)
            return
        }

        activateSession()
        player?.play()
        updateNowPlayingPlaybackState()
    }

    func stop() {
        teardownPlayer()
        pendingSeek = nil
        source = nil
        isPlaying = false
        isBuffering = false
        currentTime = 0
        duration = 0
        liveTrack = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        deactivateSession()
    }

    /// `completion` runs once this seek is over and no newer one has replaced
    /// it — which is how an episode opened at a position starts playing only
    /// after it has arrived there.
    func seek(to time: TimeInterval, completion: (() -> Void)? = nil) {
        guard !isLive, let player else {
            completion?()
            return
        }

        let target = CMTime(seconds: max(0, time), preferredTimescale: 600)
        // A second either way rather than an exact frame. Zero tolerance makes
        // AVPlayer land precisely, which over a stream means waiting for data
        // that has not arrived — going back is instant because it is already
        // buffered, going forward stalls or is dropped. A second is nothing in
        // a three hour show, and it is the difference between a scrubber that
        // works and one that works sometimes.
        let tolerance = CMTime(seconds: 1, preferredTimescale: 600)

        // Shown straight away. Waiting for the seek to land leaves the slider
        // sitting where it was for as long as the network takes.
        currentTime = max(0, time)

        seekGeneration += 1
        let generation = seekGeneration
        isSeeking = true

        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            guard let self, generation == self.seekGeneration else { return }
            self.isSeeking = false
            if finished {
                self.updateNowPlayingInfo()
            }
            // Even an unfinished seek has to hand back control, or an episode
            // that was told to start here would sit silent forever.
            completion?()
        }
    }

    func skip(by seconds: TimeInterval) {
        guard !isLive else { return }
        seek(to: currentTime + seconds)
    }

    /// Swaps a streaming podcast for its freshly downloaded file without losing position.
    func switchToLocalFile(_ fileURL: URL) {
        guard let source, case .podcast = source, player != nil else { return }
        let resumeAt = currentTime
        let wasPlaying = isPlaying

        teardownPlayer()

        let item = AVPlayerItem(url: fileURL)
        let player = AVPlayer(playerItem: item)
        self.player = player
        attachObservers(to: player, item: item)

        player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600)) { [weak self] _ in
            guard let self else { return }
            self.currentTime = resumeAt
            if wasPlaying {
                self.activateSession()
                player.play()
            }
            self.updateNowPlayingInfo()
        }
    }

    // MARK: - URL resolution

    private func resolveURL(for source: PlaybackSource) -> URL? {
        switch source {
        case .radio(let url):
            return url
        case .podcast(let podcast):
            if let fileName = podcast.fileUrl,
               case .success(let localURL) = fileService.getFile(with: fileName) {
                return localURL
            }
            return URL(string: podcast.podcastUrl)
        }
    }

    // MARK: - Player observation

    private func attachObservers(to player: AVPlayer, item: AVPlayerItem) {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPlaying = player.timeControlStatus == .playing
                self.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.updateNowPlayingPlaybackState()
            }
        }

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if item.status == .failed {
                    self.lastErrorMessage = item.error?.localizedDescription ?? "Reprodukcija nije uspela."
                    #if DEBUG
                    AppLog.write(.player, "item failed at \(self.currentTime): \(item.error?.localizedDescription ?? "-")")
                    #endif
                }
                if let itemDuration = self.player?.currentItem?.duration,
                   itemDuration.isNumeric, !itemDuration.isIndefinite {
                    self.duration = itemDuration.seconds
                    self.updateNowPlayingInfo()
                }
                if item.status == .readyToPlay, let target = self.pendingSeek {
                    self.pendingSeek = nil
                    let resumeAfterwards = self.playAfterPendingSeek
                    self.playAfterPendingSeek = false

                    self.seek(to: target) {
                        // Only now. Playing first and seeking afterwards is
                        // what let the opening seconds of an episode out of
                        // the speaker before it jumped to where it was left.
                        guard resumeAfterwards else { return }
                        self.player?.play()
                        self.updateNowPlayingPlaybackState()
                    }
                }
            }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            // Duration still updates: only the position is stale mid-seek.
            //
            // A non-finite time is not a position of zero, it is no position at
            // all — what a player reports once its item has failed or been torn
            // down. Writing it as zero threw away the one number needed to carry
            // on from where the interruption happened.
            if !self.isSeeking, time.seconds.isFinite {
                self.currentTime = time.seconds
            }
            #if DEBUG
            self.logBuffer()
            #endif
            if let itemDuration = self.player?.currentItem?.duration,
               itemDuration.isNumeric, !itemDuration.isIndefinite {
                self.duration = itemDuration.seconds
            }
        }

        // What the station announces about the current track. Costs nothing when
        // the stream carries no metadata — the delegate simply never fires.
        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput.setDelegate(self, queue: .main)
        item.add(metadataOutput)
        self.metadataOutput = metadataOutput

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isPlaying = false
            self.currentTime = self.duration
            self.updateNowPlayingPlaybackState()
        }
    }

    #if DEBUG
    /// How much of the current item the player is actually holding. On live
    /// radio it answers whether rewinding is possible at all and how large a
    /// recording window would have to be; on an episode it answers how far
    /// ahead the file has been fetched, which is how long playback can carry
    /// on with the network gone.
    ///
    /// Reads only — no player, no session, nothing that could collide with a
    /// source change.
    private func logBuffer() {
        guard let item = player?.currentItem else { return }
        guard Date().timeIntervalSince(lastBufferLog) > 5 else { return }
        lastBufferLog = Date()

        let seekable = item.seekableTimeRanges
            .map(\.timeRangeValue)
            .filter { $0.duration.seconds.isFinite }

        let seekableText = seekable
            .map { String(format: "%.0f…%.0f (%.0fs)", $0.start.seconds, $0.end.seconds, $0.duration.seconds) }
            .joined(separator: ", ")

        let loadedSeconds = item.loadedTimeRanges
            .map(\.timeRangeValue.duration.seconds)
            .filter { $0.isFinite }
            .reduce(0, +)

        AppLog.write(.player, String(format: "%@ buffer — seekable: [%@] loaded: %.1fs at %.1f",
                          isLive ? "live" : "file",
                          seekableText.isEmpty ? "none" : seekableText,
                          loadedSeconds,
                          currentTime))
    }
    #endif

    private func teardownPlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let metadataOutput {
            player?.currentItem?.remove(metadataOutput)
            self.metadataOutput = nil
        }
        isSeeking = false
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        player?.pause()
        player = nil
    }

    // MARK: - Audio session

    // AVAudioSession is an iOS idea. On the Mac there is no single session to
    // claim, no category to declare and nothing to be interrupted by — the
    // system mixes applications itself. So the three calls that matter are
    // wrapped here rather than guarded at each of their call sites, and on the
    // Mac they simply do nothing.

    private func configureAudioSession() {
        #if !targetEnvironment(macCatalyst)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
        } catch {
            AppLog.write(.player, "Audio session category failed: \(error.localizedDescription)")
        }
        #endif
    }

    private func activateSession() {
        #if !targetEnvironment(macCatalyst)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            AppLog.write(.player, "Audio session activation failed: \(error.localizedDescription)")
        }
        #endif
    }

    private func deactivateSession() {
        #if !targetEnvironment(macCatalyst)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func observeInterruptions() {
        #if !targetEnvironment(macCatalyst)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        #endif
    }

    #if !targetEnvironment(macCatalyst)
    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        #if DEBUG
        AppLog.write(.player, "interruption \(type == .began ? "began" : "ended") at \(currentTime), item: \(String(describing: player?.currentItem?.status.rawValue))")
        #endif

        switch type {
        case .began:
            pause()
        case .ended:
            guard let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            if AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }
    #endif

    // MARK: - Now Playing / remote commands

    private func configureRemoteCommands() {
        guard !commandsConfigured else { return }
        commandsConfigured = true

        let centre = MPRemoteCommandCenter.shared()

        centre.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        centre.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.toggle()
            return .success
        }

        centre.skipForwardCommand.preferredIntervals = [15]
        centre.skipForwardCommand.addTarget { [weak self] _ in
            guard let self, !self.isLive else { return .commandFailed }
            self.skip(by: 15)
            return .success
        }

        centre.skipBackwardCommand.preferredIntervals = [15]
        centre.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self, !self.isLive else { return .commandFailed }
            self.skip(by: -15)
            return .success
        }

        centre.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, !self.isLive,
                  let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: event.positionTime)
            return .success
        }
    }

    private func updateRemoteCommandAvailability() {
        let centre = MPRemoteCommandCenter.shared()
        let seekable = !isLive && hasContent
        centre.skipForwardCommand.isEnabled = seekable
        centre.skipBackwardCommand.isEnabled = seekable
        centre.changePlaybackPositionCommand.isEnabled = seekable
        centre.playCommand.isEnabled = hasContent
        centre.pauseCommand.isEnabled = hasContent
        centre.togglePlayPauseCommand.isEnabled = hasContent
    }

    private func updateNowPlayingInfo() {
        guard let source else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        // While live, the lock screen and the car should show the song rather
        // than "Radio uživo", which they already know from the live badge.
        let displayTitle = source.isLive ? (liveTrack?.title ?? source.title) : source.title
        let displayArtist: String
        if source.isLive, let liveTrack {
            displayArtist = liveTrack.artist ?? source.subtitle
        } else {
            displayArtist = source.subtitle
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: displayTitle,
            MPMediaItemPropertyArtist: displayArtist,
            MPNowPlayingInfoPropertyIsLiveStream: source.isLive,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if !source.isLive, duration > 0, duration.isFinite {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        if let image = UIImage(named: source.artworkName) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateRemoteCommandAvailability()
    }

    private func updateNowPlayingPlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            updateNowPlayingInfo()
            return
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateRemoteCommandAvailability()
    }
}

// MARK: - Stream metadata

extension PlaybackEngine: AVPlayerItemMetadataOutputPushDelegate {

    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        guard isLive else { return }

        // Written as a plain loop on purpose. The same thing as a chain of
        // flatMap/filter/compactMap made the type checker give up on this
        // expression — AVMetadataItem's overloads leave it too much to infer.
        var announced: LiveTrack?
        var sawAnyItem = false

        for group in groups {
            for item in group.items {
                sawAnyItem = true
                guard isTitleMetadata(item), let raw = item.stringValue else { continue }
                if let track = LiveTrack(raw: raw) {
                    announced = track
                }
            }
        }

        // An empty announcement between songs should clear the label rather than
        // leave the previous track sitting there as if it were still playing.
        guard announced != nil || sawAnyItem else { return }
        guard announced != liveTrack else { return }

        liveTrack = announced
        updateNowPlayingInfo()
    }

    private func isTitleMetadata(_ item: AVMetadataItem) -> Bool {
        if let identifier = item.identifier {
            if identifier == .icyMetadataStreamTitle { return true }
            if identifier == .commonIdentifierTitle { return true }
        }
        return item.commonKey == .commonKeyTitle
    }
}
