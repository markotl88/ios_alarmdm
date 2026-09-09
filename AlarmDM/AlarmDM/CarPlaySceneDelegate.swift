//
//  CarPlaySceneDelegate.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.04.2025.
//

import CarPlay
import AVFoundation
import MediaPlayer

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var isPlaying = false
    private let streamURL = URL(string: "https://stream.daskoimladja.com/proxy/daskomladja/stream")!
    
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        setupRootTemplates()
    }
    
    private func setupRootTemplates() {
        let latestPodcasts = PodcastRepository.shared.latestPodcasts()
        
        let radioTemplate = createRadioTemplate(latestPodcasts: latestPodcasts)
        let showsTemplate = createShowsTemplate()

        radioTemplate.tabTitle = "Radio"
        radioTemplate.tabImage = UIImage(systemName: "dot.radiowaves.left.and.right") // 📡

        showsTemplate.tabTitle = "Shows"
        showsTemplate.tabImage = UIImage(systemName: "music.note.list") // 🎶📃

        let tabBarTemplate = CPTabBarTemplate(templates: [radioTemplate, showsTemplate])
        interfaceController?.setRootTemplate(tabBarTemplate, animated: true, completion: nil)
    }
    
    private func createBookmarkTemplate() -> CPListTemplate {
        let infoItem = CPListItem(text: "Bookmark", detailText: "Biće dostupno uskoro")
        let section = CPListSection(items: [infoItem])
        let template = CPListTemplate(title: "Bookmark", sections: [section])
        return template
    }
    
    private func createRadioTemplate(latestPodcasts: [Podcast]) -> CPListTemplate {
        // --- Radio uživo dugme ---
        let radioItem = CPListItem(
            text: "Radio uživo",
            detailText: isPlaying ? "⏹️ Zaustavi" : "▶️ Pusti"
        )
        radioItem.handler = { [weak self] _, completion in
            guard let self else { return }
            if self.isPlaying {
                RadioPlayer.shared.stop()
            } else {
                RadioPlayer.shared.playStream(url: self.streamURL)
                
                var nowPlaying: [String: Any] = [
                    MPMediaItemPropertyTitle: "Radio Uživo",
                    MPMediaItemPropertyArtist: "Daško i Mladja",
                ]

                if let image = UIImage(named: "iTunesArtwork") {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    nowPlaying[MPMediaItemPropertyArtwork] = artwork
                }
                
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
                
                interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            }
            self.isPlaying.toggle()
            completion()
        }
        
        // Sekcija za Radio uživo
        let radioSection = CPListSection(items: [radioItem], header: "Radio uživo", sectionIndexTitle: "")

        // --- Poslednjih 5 podkasta ---
        let podcastItems = latestPodcasts.prefix(10).map { podcast in
            let showImage = UIImage(named: podcast.show.imageName) // ← uzimamo iz Show enum-a
            let item = CPListItem(text: podcast.title, detailText: podcast.subtitle, image: showImage)
            item.handler = { [weak self] _, completion in
                self?.presentEpisodeOptions(for: podcast)
                completion()
            }
            return item
        }
        // Sekcija za podkaste
        let podcastsSection = CPListSection(items: podcastItems, header: "Najnoviji podkasti", sectionIndexTitle: "")

        // --- Sastavljanje ---
        let template = CPListTemplate(title: "Slušaj Radio", sections: [radioSection, podcastsSection])
        template.tabTitle = "Radio"
        return template
    }
    
    private func createShowsTemplate() -> CPListTemplate {
        let viewModel = ShowViewModel()
        
        let showItems = viewModel.shows.map { show in
            let showImage = UIImage(named: show.imageName)
            let item = CPListItem(text: show.displayName, detailText: show.description, image: showImage)
            item.handler = { [weak self] _, completion in
                // Ovde možeš kasnije da otvoriš listu epizoda za taj show
                self?.showEpisodes(for: show)
                completion()
            }
            return item
        }
        
        let section = CPListSection(items: showItems)
        let template = CPListTemplate(title: "Podcasti", sections: [section])
        template.tabTitle = "Podcasti"
        return template
    }
    
    private func showEpisodes(for show: Show) {
        let podcasts = PodcastRepository.shared.latestPodcasts(limit: 20).filter {
            $0.show == show
        }
        
        let items: [CPListItem] = podcasts.map { podcast in
            let showImage = UIImage(named: podcast.show.imageName)
            let item = CPListItem(text: podcast.title, detailText: podcast.subtitle, image: showImage)
            item.handler = { [weak self] _, completion in
                guard let url = URL(string: podcast.podcastUrl) else { return }
                self?.presentEpisodeOptions(for: podcast)
                completion()
            }
            return item
        }
        
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: show.displayName, sections: [section])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }
    
    private func presentEpisodeOptions(for podcast: Podcast) {
        let isDownloaded = checkIfDownloaded(podcast: podcast) // tvoja logika

        let playItem = CPListItem(text: "▶️ Pusti epizodu", detailText: podcast.title)
        playItem.handler = { [weak self] _, completion in
            guard let url = URL(string: podcast.podcastUrl) else { return }
            RadioPlayer.shared.playStream(url: url)

            var nowPlaying: [String: Any] = [
                MPMediaItemPropertyTitle: podcast.title,
                MPMediaItemPropertyArtist: podcast.show.displayName,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
                MPMediaItemPropertyPlaybackDuration: podcast.durationInSeconds
            ]

            if let image = UIImage(named: podcast.show.imageName) {
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                nowPlaying[MPMediaItemPropertyArtwork] = artwork
            }
            
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying

            self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)

            completion()
        }

        let bookmarkItem = CPListItem(text: "🔖 Bookmarkuj trenutak", detailText: "Bookmark")
        bookmarkItem.handler = { [weak self] _, completion in
            // snimi poziciju u AVPlayer-u
            let time = RadioPlayer.shared.currentTime()
            self?.saveBookmark(for: podcast, at: time)
            completion()
        }

        let downloadItem = CPListItem(
            text: isDownloaded ? "✅ Već preuzeto" : "⬇️ Preuzmi epizodu", detailText: "Download"
        )
        downloadItem.handler = { [weak self] _, completion in
            if !isDownloaded {
                self?.downloadPodcast(podcast)
            }
            completion()
        }

        let section = CPListSection(items: [playItem, bookmarkItem, downloadItem])
        let template = CPListTemplate(title: podcast.title, sections: [section])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }
    
    private func checkIfDownloaded(podcast: Podcast) -> Bool {
        // TODO: Implementiraj lokalnu proveru
        return false
    }

    private func saveBookmark(for podcast: Podcast, at time: Double) {
        // TODO: Sačuvaj u UserDefaults, Realm, itd.
        print("📌 Saved bookmark at \(time)s for \(podcast.title)")
    }

    private func downloadPodcast(_ podcast: Podcast) {
        // TODO: Implement download logic
        print("⬇️ Downloading \(podcast.title)")
    }
}

class RadioPlayer {
    static let shared = RadioPlayer()
    private var player: AVPlayer?
    func currentTime() -> Double {
        return player?.currentTime().seconds ?? 0
    }
    
    func playStream(url: URL) {
        player = AVPlayer(url: url)
        
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        
        configureRemoteCommands()
        
        player?.play()
    }

    func stop() {
        player?.pause()
        player = nil
    }
    
    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.player?.play()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            return .success
        }
    }
}

// MOCK modeli za testiranje

import RealmSwift

final class PodcastRepository {
    static let shared = PodcastRepository()
    
    private let realm = try! Realm()
    
    func latestPodcasts(limit: Int = 10) -> [Podcast] {
        let podcastRealms = realm.objects(PodcastRealm.self)
            .sorted(byKeyPath: "createdAt", ascending: false)
        
        return Array(podcastRealms.prefix(limit)).map { Podcast(from: $0) }
    }
}
