//
//  AudioPlayer.swift
//  AlarmDM
//
//  Created by Marko Stajic on 23.10.2024.
//

import Foundation
import AVFoundation

protocol AudioPlayer {
    func play(url: URL, completion: (Bool) -> Void)
    func pause()
    func resume()
    func getCurrentTime() -> TimeInterval
    func setCurrentTime(_ time: TimeInterval)
    func switchToDownloadedFile(file: URL, completion: (Bool) -> Void)
}

class PodcastAudioPlayer: AudioPlayer {
    private var avPlayer: AVPlayer?
    private var avAudioPlayer: AVAudioPlayer?
    private var isUsingStream: Bool = true
    private var currentPlaybackTime: TimeInterval = 0

    func play(url: URL, completion: (Bool) -> Void) {
        if url.isFileURL {
            setupAVAudioPlayer(with: url, completion: { isPlaying in
                completion(isPlaying)
            })
        } else {
            setupAVPlayer(with: url, completion: { isPlaying in
                completion(isPlaying)
            })
        }
    }
    
    func switchToDownloadedFile(file: URL, completion: (Bool) -> Void) {
        // Get the current playback time from AVPlayer (stream)
        let currentTime = getCurrentTime()
        
        // Pause the AVPlayer (stream)
        pause()
        
        // Set up the AVAudioPlayer (local file) with the same playback time
        setupAVAudioPlayer(with: file, completion: { [weak self] isPlaying in
            guard let self = self else { return }
            if isPlaying {
                // Set the playback time to resume from where the stream left off
                self.setCurrentTime(currentTime)
                self.resume() // Start playing from the same point
                completion(true)
            } else {
                print("Error switching to downloaded file.")
                completion(false)
            }
        })
    }
    
    private func setupAVPlayer(with url: URL, completion: (Bool) -> Void) {
        avPlayer = AVPlayer(url: url)
        avPlayer?.play()
        isUsingStream = true
        completion(true)
    }

    private func setupAVAudioPlayer(with fileUrl: URL, completion: (Bool) -> Void) {
        do {
            avAudioPlayer = try AVAudioPlayer(contentsOf: fileUrl)
            avAudioPlayer?.currentTime = currentPlaybackTime
            avAudioPlayer?.play()
            isUsingStream = false
            completion(true)
        } catch {
            print("Error setting up AVAudioPlayer: \(error)")
            completion(false)
        }
    }

    func pause() {
        if isUsingStream {
            avPlayer?.pause()
        } else {
            avAudioPlayer?.pause()
        }
    }

    func resume() {
        if isUsingStream {
            avPlayer?.play()
        } else {
            avAudioPlayer?.play()
        }
    }

    func getCurrentTime() -> TimeInterval {
        return isUsingStream ? CMTimeGetSeconds(avPlayer?.currentTime() ?? CMTime.zero) : avAudioPlayer?.currentTime ?? 0
    }

    func setCurrentTime(_ time: TimeInterval) {
        if isUsingStream {
            avPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        } else {
            avAudioPlayer?.currentTime = time
        }
    }
}
