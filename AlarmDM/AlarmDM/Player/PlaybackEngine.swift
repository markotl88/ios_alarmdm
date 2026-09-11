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

final class PlaybackEngine: NSObject, ObservableObject {

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
    private var metadataOutput: AVPlayerItemMetadataOutput?
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
        if self.source == source, player != nil {
            if let position { seek(to: position) }
            resume()
            return
        }

        pendingSeek = position

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
        guard player != nil else {
            if let source { play(source) }
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func seek(to time: TimeInterval) {
        guard !isLive, let player else { return }
        let target = CMTime(seconds: max(0, time), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.currentTime = max(0, time)
            self?.updateNowPlayingInfo()
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
                }
                if let itemDuration = self.player?.currentItem?.duration,
                   itemDuration.isNumeric, !itemDuration.isIndefinite {
                    self.duration = itemDuration.seconds
                    self.updateNowPlayingInfo()
                }
                if item.status == .readyToPlay, let target = self.pendingSeek {
                    self.pendingSeek = nil
                    self.seek(to: target)
                }
            }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds.isFinite ? time.seconds : 0
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
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        player?.pause()
        player = nil
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
        } catch {
            debugPrint("Audio session category failed: \(error.localizedDescription)")
        }
    }

    private func activateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            debugPrint("Audio session activation failed: \(error.localizedDescription)")
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

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
