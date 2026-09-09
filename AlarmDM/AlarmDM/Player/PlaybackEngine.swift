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

    // Publishers exposed explicitly: the stored properties are private(set), so
    // consumers observe through these instead of the synthesised $ projections.
    var sourcePublisher: AnyPublisher<PlaybackSource?, Never> { $source.eraseToAnyPublisher() }
    var isPlayingPublisher: AnyPublisher<Bool, Never> { $isPlaying.eraseToAnyPublisher() }
    var isBufferingPublisher: AnyPublisher<Bool, Never> { $isBuffering.eraseToAnyPublisher() }
    var currentTimePublisher: AnyPublisher<TimeInterval, Never> { $currentTime.eraseToAnyPublisher() }
    var durationPublisher: AnyPublisher<TimeInterval, Never> { $duration.eraseToAnyPublisher() }

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
    func play(_ source: PlaybackSource) {
        if self.source == source, player != nil {
            resume()
            return
        }

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
        source = nil
        isPlaying = false
        isBuffering = false
        currentTime = 0
        duration = 0
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

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: source.title,
            MPMediaItemPropertyArtist: source.subtitle,
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
