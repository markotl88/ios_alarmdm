//
//  PlayerViewModel.swift
//  AlarmDM
//
//  Created by Marko Stajic on 25.10.2024.
//


import Foundation
import Combine
import RealmSwift
import AVFoundation

enum PlayerMode: Equatable, Identifiable {
    var id: UUID {
        switch self {
        case .radio:
            return UUID(uuidString: "00000000-0000-0000-0000-000000000001")! // Fixed UUID for radio mode
        case .podcast(let podcast):
            return podcast.id // Use podcast ID if it's already a UUID
        }
    }

    case radio(stream: URL?)
    case podcast(podcast: Podcast)
}

class PlayerViewModel: ObservableObject {
    
    private let audioPlayer: AudioPlayer
    @Published var isPresented = false

    @Published var mode: PlayerMode? {
        didSet {
            switch mode {
            case .radio(let stream):
                onlineStream = stream
                podcastId = nil
                title = "Radio"
                subtitle = "Uživo"
            case .podcast(let podcast):
                onlineStream = nil
                podcastId = podcast.id
                title = podcast.title
                subtitle = podcast.subtitle
            case .none:
                onlineStream = nil
                podcastId = nil
                title = ""
                subtitle = ""
            }

            if let podcastId = podcastId {
                podcast = loadPodcastFromRealm(with: podcastId)
                isDownloaded = checkIfDownloaded()
            } else {
                podcast = nil
                isDownloaded = false
            }
        }
    }
    @Published var isDownloaded: Bool = false
    @Published var progress: Double = 0.0
    @Published var isExpanded: Bool = false
    @Published var isPlaying: Bool = false
    @Published var isDownloading: Bool = false
    @Published var showDeleteButton: Bool = false // Manage visibility of the delete button
    @Published var showCheckmark: Bool = false // Manage visibility of the checkmark
    @Published var title: String = ""
    @Published var subtitle: String = ""
    
    let id = UUID() // This makes the view model identifiable
        
    private let fileService: FileServiceProtocol
    private let podcastService: PodcastServiceProtocol
    private var podcastId: UUID?
    private var podcast: Podcast?
    private let realm = try? Realm()
    private var onlineStream: URL?
    private var isAudioSetup: Bool = false // Flag to track if audio setup is done

    init(mode: PlayerMode? = nil,
         audioPlayer: AudioPlayer = PodcastAudioPlayer(),
         podcastService: PodcastServiceProtocol = PodcastService(),
         fileService: FileServiceProtocol = FileService()) {
        
        self.mode = mode
        self.audioPlayer = audioPlayer
        self.fileService = fileService
        self.podcastService = podcastService

        switch mode {
        case .radio(let stream):
            self.onlineStream = stream
            self.podcastId = nil
            self.title = "Radio"
            self.subtitle = "Uživo"
        case .podcast(let podcast):
            self.onlineStream = nil
            self.podcastId = podcast.id
            self.title = podcast.title
            self.subtitle = podcast.subtitle
        case .none:
            self.onlineStream = nil
            self.podcastId = nil
            self.title = ""
            self.subtitle = ""
        }

        // Load initial data if needed
        if let podcastId = podcastId {
            self.podcast = loadPodcastFromRealm(with: podcastId)
            self.isDownloaded = checkIfDownloaded()
        }
    }

    private func setup() {
        if let podcastId = podcastId {
            self.podcast = loadPodcastFromRealm(with: podcastId)
            self.title = self.podcast?.title ?? ""
            self.subtitle = self.podcast?.subtitle ?? ""
        } else {
            self.title = "Radio"
            self.subtitle = "Uživo"
        }
        
        self.isDownloaded = checkIfDownloaded()
    }

    private func loadPodcastFromRealm(with id: UUID) -> Podcast? {
        guard let realm = try? Realm(),
              let podcastRealm = realm.objects(PodcastRealm.self)
                .filter("id == %@", id.uuidString).first else {
            debugPrint("Podcast \(id) not found in Realm")
            return nil
        }
        return Podcast(from: podcastRealm)
    }
    
    func toggleDeleteButton() {
        guard let podcast = podcast else { return }
        showDeleteButton = podcast.isDownloaded
    }
    
    func setupAudioPlayer(forPodcast: Bool) {
        
        if forPodcast {
            if let fileName = podcast?.fileUrl,
               case .success(let file) = fileService.getFile(with: fileName) {
                print("Local file found: \(file)")
                audioPlayer.play(url: file, completion: { [weak self] isPlaying in
                    self?.isPlaying = isPlaying
                })
            } else if let podcastUrl = podcast?.podcastUrl, let onlineFile = URL(string: podcastUrl) {
                print("Local file not found, falling back to online: \(onlineFile)")
                audioPlayer.play(url: onlineFile, completion: { [weak self] isPlaying in
                    self?.isPlaying = isPlaying
                })
            } else {
                print("Error: No file to play")
            }
        } else {
            if let onlineFile = onlineStream {
                print("Online radio is playing: \(onlineFile)")
                audioPlayer.play(url: onlineFile, completion: { [weak self] isPlaying in
                    self?.isPlaying = isPlaying
                })
            } else {
                print("Error: No file to play")
            }
        }
        
        isAudioSetup = true
    }

    // MARK: - Play/Pause Toggle
    func togglePlayPause() {
        
        if !isAudioSetup {
            setupAudioPlayer(forPodcast: onlineStream == nil)
        } else {
            if isPlaying {
                audioPlayer.pause()
            } else {
                audioPlayer.resume()
            }
            isPlaying.toggle()
        }
    }

    // MARK: - Download Podcast
    func downloadPodcast() {
        guard let url = podcast?.podcastUrl, let podcastUrl = URL(string: url) else {
            return
        }
        
        isDownloading = true
        showCheckmark = false // Ensure checkmark is hidden initially

        podcastService.downloadPodcasts(from: podcastUrl,
                                        completion: { [weak self] result in
            guard let self else { return }
            self.isDownloading = false
            switch result {
            case .success(let tempLocation):
                
                self.isDownloaded = true
                self.podcast?.fileUrl = tempLocation.lastPathComponent
                if let podcast = self.podcast {
                    self.savePodcastToRealm(PodcastRealm(from: podcast))
                }
                // Show checkmark and then delete button
                self.showCheckmark = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.showCheckmark = false
                    self.showDeleteButton = true
                }
                if isPlaying {
                    audioPlayer.switchToDownloadedFile(file: tempLocation, completion: { isPlaying in
                        self.isPlaying = isPlaying
                    })
                }
            case .failure(let error):
                debugPrint("Error downloading file: \(error.localizedDescription)")
            }
        }, progressHandler: { [weak self] progress in
            guard let self = self else { return }
            self.progress = progress
        })
    }

    // MARK: - Save Podcast to Realm
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
    
    // MARK: - Delete Podcast
    func deletePodcast() {
        guard let podcast = podcast, let fileName = podcast.fileUrl else {
            return
        }

        let result = fileService.deleteFile(with: fileName)
        switch result {
        case .success(let success):
            isDownloaded = false
            showDeleteButton = false // Hide the delete button after the file is deleted
            self.podcast?.fileUrl = nil // Clear the file URL
            savePodcastToRealm(PodcastRealm(from: podcast))
        case .failure(let failure):
            debugPrint("Error deleting file: \(failure.localizedDescription)")
        }
    }

    // MARK: - Check if Podcast is Downloaded
    private func checkIfDownloaded() -> Bool {
        guard let podcastId = podcastId,
              let podcastRealm = realm?.objects(PodcastRealm.self).filter("id == %@", podcastId.uuidString).first else {
            return false
        }
        return Podcast(from: podcastRealm).isDownloaded
    }
}
