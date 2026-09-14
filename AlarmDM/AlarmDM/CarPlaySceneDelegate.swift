//
//  CarPlaySceneDelegate.swift
//  AlarmDM
//
//  CarPlay is a second face on the same player: every action here goes through
//  PlaybackEngine.shared, the same object the phone UI drives. Nothing owns its
//  own AVPlayer, so audio never doubles up when the user gets in the car.
//

// CarPlay does not exist on the Mac, and neither does the framework — the
// whole file is compiled out there rather than guarded piece by piece.
#if !targetEnvironment(macCatalyst)

import CarPlay
import UIKit
import AVFoundation
import MediaPlayer
import Combine

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()

    private var radioItem: CPListItem?
    private var engine: PlaybackEngine { .shared }

    /// The bookmark button briefly fills in after a capture. CPNowPlayingButton
    /// cannot be changed once made, so the acknowledgement is a rebuilt button
    /// rather than an edited one.
    private var justBookmarked = false
    private var bookmarkFeedback: Task<Void, Never>?

    // MARK: - Scene lifecycle

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        setupRootTemplates()
        observeEngine()
        CPNowPlayingTemplate.shared.add(self)
        refreshNowPlayingButtons()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        cancellables.removeAll()
        bookmarkFeedback?.cancel()
        CPNowPlayingTemplate.shared.remove(self)
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
        let item = CPListItem(
            text: "Radio uživo",
            detailText: radioDetailText,
            image: UIImage(named: "img_radio")?.fittedToCarPlayListItem()
        )
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
        let items = Show.listed.map { show -> CPListItem in
            let item = CPListItem(
                text: show.displayName,
                detailText: show.description,
                image: UIImage(named: show.imageName)?.fittedToCarPlayListItem()
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
            image: UIImage(named: podcast.show.imageName)?.fittedToCarPlayListItem()
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

    // MARK: - Bookmarks

    /// It saves on the press. Anything that asks a follow-up question — a
    /// category, a confirmation — is a menu to read while driving, which is the
    /// one thing this cannot be.
    ///
    /// Two ways into the same action, because CarPlay only offers one of each.
    /// The row under the transport controls takes images and nothing else, so
    /// the glyph there is drawn heavy rather than at its default weight. The Up
    /// Next slot is the only part of Now Playing that accepts a word, and a
    /// labelled target is easier to hit without looking than a small symbol.
    private func refreshNowPlayingButtons() {
        let template = CPNowPlayingTemplate.shared

        guard engine.hasContent else {
            template.updateNowPlayingButtons([])
            template.isUpNextButtonEnabled = false
            return
        }

        if let image = UIImage.carPlayButtonSymbol(justBookmarked ? "bookmark.fill" : "bookmark") {
            let button = CPNowPlayingImageButton(image: image) { [weak self] _ in
                self?.captureBookmark()
            }
            template.updateNowPlayingButtons([button])
        }

        // The one piece of text the car can show back, so the acknowledgement
        // is a word rather than a glyph that changed shape.
        template.upNextTitle = justBookmarked ? "Zabeleženo" : "Zabeleži"
        template.isUpNextButtonEnabled = true
    }

    private func captureBookmark() {
        guard BookmarkLibrary.shared.capture(origin: .car) != nil else { return }

        justBookmarked = true
        refreshNowPlayingButtons()

        bookmarkFeedback?.cancel()
        bookmarkFeedback = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.justBookmarked = false
            self?.refreshNowPlayingButtons()
        }
    }

    // MARK: - Engine observation

    private func observeEngine() {
        engine.isPlayingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshRadioItem() }
            .store(in: &cancellables)

        engine.sourcePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshRadioItem()
                // The button belongs to whatever is playing, so it comes and
                // goes with it rather than sitting there doing nothing.
                self?.refreshNowPlayingButtons()
            }
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

// MARK: - Now Playing observer

extension CarPlaySceneDelegate: CPNowPlayingTemplateObserver {

    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        captureBookmark()
    }
}

// MARK: - Artwork sizing

private extension UIImage {

    /// A bookmark is taller than it is wide, and CarPlay fits button images
    /// into a square — so the glyph came out stretched. Drawing it centred on
    /// a square canvas keeps its own proportions and lets the empty space do
    /// the fitting instead.
    static func carPlayButtonSymbol(_ name: String) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return nil }

        let side = max(symbol.size.width, symbol.size.height)
        let canvas = CGSize(width: side, height: side)

        let squared = UIGraphicsImageRenderer(size: canvas).image { _ in
            symbol.draw(in: CGRect(
                x: (side - symbol.size.width) / 2,
                y: (side - symbol.size.height) / 2,
                width: symbol.size.width,
                height: symbol.size.height
            ))
        }
        // Rendering flattens the symbol to pixels, so the tint has to be asked
        // for again or CarPlay would draw it black on black.
        return squared.withRenderingMode(.alwaysTemplate)
    }

    /// CarPlay renders list thumbnails at a fixed size and scales anything larger
    /// on every draw. The show covers are 1024², so they are resized once here.
    func fittedToCarPlayListItem() -> UIImage {
        let target = CPListItem.maximumImageSize
        guard size.width > target.width || size.height > target.height else { return self }

        let scale = min(target.width / size.width, target.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)

        return UIGraphicsImageRenderer(size: fitted).image { _ in
            draw(in: CGRect(origin: .zero, size: fitted))
        }
    }
}

#endif
