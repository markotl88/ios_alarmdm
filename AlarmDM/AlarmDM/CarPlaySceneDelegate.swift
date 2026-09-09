//
//  CarPlaySceneDelegate.swift
//  AlarmDM
//
//  CarPlay is a second face on the same player: every action here goes through
//  PlaybackEngine.shared, the same object the phone UI drives. Nothing owns its
//  own AVPlayer, so audio never doubles up when the user gets in the car.
//

import CarPlay
import AVFoundation
import MediaPlayer
import Combine
import RealmSwift

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()

    private var radioItem: CPListItem?
    private var engine: PlaybackEngine { .shared }

    // MARK: - Scene lifecycle

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        setupRootTemplates()
        observeEngine()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        cancellables.removeAll()
        self.interfaceController = nil
        self.radioItem = nil
    }

    // MARK: - Templates

    private func setupRootTemplates() {
        let radioTemplate = makeRadioTemplate()
        let showsTemplate = makeShowsTemplate()

        radioTemplate.tabTitle = "Radio"
        radioTemplate.tabImage = UIImage(systemName: "dot.radiowaves.left.and.right")

        showsTemplate.tabTitle = "Emisije"
        showsTemplate.tabImage = UIImage(systemName: "music.note.list")

        let tabBarTemplate = CPTabBarTemplate(templates: [radioTemplate, showsTemplate])
        interfaceController?.setRootTemplate(tabBarTemplate, animated: true, completion: nil)
    }

    private func makeRadioTemplate() -> CPListTemplate {
        let item = CPListItem(text: "Radio uživo", detailText: radioDetailText)
        item.handler = { [weak self] _, completion in
            self?.toggleRadio()
            completion()
        }
        self.radioItem = item

        let radioSection = CPListSection(items: [item], header: "Uživo", sectionIndexTitle: nil)

        let latest = PodcastRepository.shared.latestPodcasts(limit: 10)
        let podcastSection = CPListSection(
            items: latest.map { listItem(for: $0) },
            header: "Najnoviji podkasti",
            sectionIndexTitle: nil
        )

        let template = CPListTemplate(title: "Radio", sections: [radioSection, podcastSection])
        template.tabTitle = "Radio"
        return template
    }

    private func makeShowsTemplate() -> CPListTemplate {
        let items = Show.allCases.map { show -> CPListItem in
            let item = CPListItem(
                text: show.displayName,
                detailText: show.description,
                image: UIImage(named: show.imageName)
            )
            item.handler = { [weak self] _, completion in
                self?.pushEpisodes(for: show)
                completion()
            }
            return item
        }

        let template = CPListTemplate(title: "Emisije", sections: [CPListSection(items: items)])
        template.tabTitle = "Emisije"
        return template
    }

    private func pushEpisodes(for show: Show) {
        let episodes = PodcastRepository.shared.latestPodcasts(limit: 100).filter { $0.show == show }

        let template: CPListTemplate
        if episodes.isEmpty {
            let empty = CPListItem(text: "Nema preuzetih epizoda", detailText: "Otvori aplikaciju na telefonu da osvežiš listu.")
            template = CPListTemplate(title: show.displayName, sections: [CPListSection(items: [empty])])
        } else {
            template = CPListTemplate(
                title: show.displayName,
                sections: [CPListSection(items: episodes.map { listItem(for: $0) })]
            )
        }

        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    /// One tap plays the episode — no intermediate menu. CarPlay guidelines want
    /// the shortest possible path to audio while driving.
    private func listItem(for podcast: Podcast) -> CPListItem {
        let detail = podcast.isDownloaded ? "Preuzeto · \(podcast.subtitle)" : podcast.subtitle
        let item = CPListItem(
            text: podcast.title,
            detailText: detail,
            image: UIImage(named: podcast.show.imageName)
        )

        if case .podcast(let playing) = engine.source, playing.id == podcast.id {
            item.isPlaying = true
        }

        item.handler = { [weak self] _, completion in
            guard let self else { completion(); return }
            self.engine.play(.podcast(podcast))
            self.pushNowPlaying()
            completion()
        }
        return item
    }

    // MARK: - Transport

    private func toggleRadio() {
        if case .radio = engine.source {
            engine.toggle()
        } else if let url = AppConstants.fallbackStreamURL {
            engine.play(.radio(url: url))
        }
        pushNowPlaying()
    }

    private func pushNowPlaying() {
        guard let interfaceController else { return }
        // Avoid stacking duplicate Now Playing templates.
        if interfaceController.topTemplate === CPNowPlayingTemplate.shared { return }
        interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }

    // MARK: - Engine observation

    private func observeEngine() {
        engine.isPlayingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshRadioItem() }
            .store(in: &cancellables)

        engine.sourcePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshRadioItem() }
            .store(in: &cancellables)
    }

    private func refreshRadioItem() {
        radioItem?.setDetailText(radioDetailText)
        if case .radio = engine.source {
            radioItem?.isPlaying = engine.isPlaying
        } else {
            radioItem?.isPlaying = false
        }
    }

    private var radioDetailText: String {
        if case .radio = engine.source {
            return engine.isPlaying ? "Zaustavi" : "Nastavi"
        }
        return "Pusti"
    }
}

// MARK: - Realm access for CarPlay

final class PodcastRepository {
    static let shared = PodcastRepository()

    func latestPodcasts(limit: Int = 10) -> [Podcast] {
        guard let realm = try? Realm() else {
            debugPrint("Realm unavailable, returning no podcasts")
            return []
        }
        let podcastRealms = realm.objects(PodcastRealm.self)
            .sorted(byKeyPath: "createdAt", ascending: false)

        return Array(podcastRealms.prefix(limit)).map { Podcast(from: $0) }
    }
}
