//
//  CarPlaySceneDelegate.swift
//  AlarmDM
//
//  CarPlay is a second face on the same player: every action here goes through
//  PlaybackEngine.shared, the same object the phone UI drives. Nothing owns its
//  own AVPlayer, so audio never doubles up when the user gets in the car.
//

// CarPlay does not exist on the Mac, and neither does the framework - the
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
    /// The carry-on row and the episode it names, kept so the one string on
    /// it that moves can be rewritten without rebuilding anything.
    private var continueItem: CPListItem?
    private var continuePodcast: Podcast?
    /// Kept so the sections can be rebuilt in place. Replacing the root
    /// template instead would throw away wherever the person had navigated
    /// to, which in a car is worse than a stale row.
    private var radioTemplate: CPListTemplate?
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

        #if DEBUG
        AppLog.write(.carplay, "carplay connected")
        #endif

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
        self.continueItem = nil
        self.continuePodcast = nil
        self.radioTemplate = nil
    }

    // MARK: - Templates

    private func setupRootTemplates() {
        let radioTemplate = makeRadioTemplate()
        let showsTemplate = makeShowsTemplate()

        radioTemplate.tabTitle = String(localized: "Radio")
        radioTemplate.tabImage = UIImage(systemName: "dot.radiowaves.left.and.right")

        showsTemplate.tabTitle = String(localized: "Emisije")
        showsTemplate.tabImage = UIImage(systemName: "music.note.list")

        let tabBarTemplate = CPTabBarTemplate(templates: [radioTemplate, showsTemplate])
        setRoot(tabBarTemplate, retriesLeft: 2)
    }

    /// A blank CarPlay screen with the audio still playing means the root
    /// template never landed - the scene is connected and nothing was ever
    /// handed to it. It is the one failure here with no visible cause, since
    /// CarPlay says nothing and the app carries on, so the result is asked for
    /// and a failure is tried again rather than left as an empty screen.
    private func setRoot(_ template: CPTemplate, retriesLeft: Int) {
        guard let interfaceController else { return }

        interfaceController.setRootTemplate(template, animated: true) { [weak self] done, error in
            #if DEBUG
            AppLog.write(.carplay, "carplay root template: \(done ? "shown" : "refused")\(error.map { " - \($0.localizedDescription)" } ?? "")")
            #endif

            guard !done, retriesLeft > 0 else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.setRoot(template, retriesLeft: retriesLeft - 1)
            }
        }
    }

    private func makeRadioTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: String(localized: "Radio"), sections: radioSections())
        template.tabTitle = String(localized: "Radio")
        self.radioTemplate = template
        return template
    }

    /// First what you were in the middle of, then the radio, then what is new.
    ///
    /// Getting out of the car and back in is the ordinary case, and until now
    /// it meant finding the episode again on the phone: the car knew what was
    /// playing only while it was playing. The first row is that episode, with
    /// the second it stopped on.
    private func radioSections() -> [CPListSection] {
        let item = CPListItem(
            text: String(localized: "Radio uživo"),
            detailText: radioDetailText,
            image: UIImage(named: "img_radio")?.fittedToCarPlayListItem()
        )
        item.handler = { [weak self] _, completion in
            self?.openRadio()
            completion()
        }
        self.radioItem = item

        let radioSection = CPListSection(items: [item], header: String(localized: "Uživo"), sectionIndexTitle: nil)

        let latest = PodcastRepository.shared.latestPodcasts(limit: 10)
        let bothCuts = latest.showsInBothCuts
        let podcastSection = CPListSection(
            items: latest.map { listItem(for: $0, marksCut: bothCuts.contains($0.show)) },
            header: String(localized: "Najnovije epizode"),
            sectionIndexTitle: nil
        )

        guard let unfinished = continueListening() else {
            continueItem = nil
            continuePodcast = nil
            return [radioSection, podcastSection]
        }

        let carryOn = listItem(for: unfinished,
                               detail: continueDetail(for: unfinished),
                               marksCut: bothCuts.contains(unfinished.show))
        continueItem = carryOn
        continuePodcast = unfinished

        let continueSection = CPListSection(
            items: [carryOn],
            header: String(localized: "Nastavi"),
            sectionIndexTitle: nil
        )

        return [continueSection, radioSection, podcastSection]
    }

    /// What is loaded right now, or failing that the last thing left unfinished.
    private func continueListening() -> Podcast? {
        if case .podcast(let playing) = engine.source { return playing }
        return PodcastRepository.shared.lastListened()
    }

    private func continueDetail(for podcast: Podcast) -> String {
        let seconds = engine.source.flatMap { source -> TimeInterval? in
            guard case .podcast(let playing) = source, playing.id == podcast.id else { return nil }
            return engine.currentTime
        } ?? podcast.playedPosition

        guard seconds > 0 else { return podcast.subtitle }
        return String(localized: "Od \(ScrubberView.format(seconds)) · \(podcast.subtitle)")
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

        let template = CPListTemplate(title: String(localized: "Emisije"), sections: [CPListSection(items: items)])
        template.tabTitle = String(localized: "Emisije")
        return template
    }

    private func pushEpisodes(for show: Show) {
        let episodes = PodcastRepository.shared.latestPodcasts(limit: 100).filter { $0.show == show }

        let template: CPListTemplate
        if episodes.isEmpty {
            let empty = CPListItem(text: String(localized: "Nema učitanih epizoda"),
                                   detailText: String(localized: "Otvori aplikaciju na telefonu da osvežiš listu."))
            template = CPListTemplate(title: show.displayName, sections: [CPListSection(items: [empty])])
        } else {
            template = CPListTemplate(
                title: show.displayName,
                sections: [CPListSection(items: episodes.map {
                    listItem(for: $0, marksCut: episodes.showsInBothCuts.contains($0.show))
                })]
            )
        }

        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    /// One tap plays the episode - no intermediate menu. CarPlay guidelines want
    /// the shortest possible path to audio while driving.
    private func listItem(for podcast: Podcast, detail: String? = nil, marksCut: Bool = false) -> CPListItem {
        let detail = detail ?? (podcast.isDownloaded ? String(localized: "Preuzeto · \(podcast.subtitle)") : podcast.subtitle)
        let item = CPListItem(
            text: podcast.title,
            detailText: detail,
            image: UIImage(named: podcast.show.imageName)?.fittedToCarPlayListItem()
        )

        // CarPlay draws the bar itself, under the row, which is the one place
        // on that screen with room to spare. Full for a finished episode: from
        // a car seat a full bar says "heard" faster than any mark could.
        item.playbackProgress = CGFloat(podcast.listeningProgress ?? (podcast.isPlayed ? 1 : 0))

        // The two cuts of one day have the same title, so on this screen they
        // were two identical rows. The one without music is marked, where the
        // eye ends a row; the one with music is the show as it went out and
        // is left plain, as it is everywhere else.
        if marksCut && !podcast.isWithMusic {
            item.setAccessoryImage(Self.withoutMusicMark)
        }

        if case .podcast(let playing) = engine.source, playing.id == podcast.id {
            item.isPlaying = true
        }

        item.handler = { [weak self] _, completion in
            guard let self else { completion(); return }

            if case .podcast(let playing) = self.engine.source, playing.id == podcast.id {
                // Already loaded: carry on rather than open it again, and
                // never stop it - see openRadio.
                if !self.engine.isPlaying { self.engine.resume() }
            } else {
                // Where the app would have started it. The rule lives in the
                // repository precisely so the car cannot have its own.
                self.engine.play(
                    .podcast(podcast),
                    startingAt: PodcastRepository.shared.resumePosition(for: podcast.id)
                )
            }

            self.pushNowPlaying()
            completion()
        }
        return item
    }

    /// Drawn once. Template images, so CarPlay tints them for its own light
    /// and dark modes rather than drawing black on black.
    private static let withoutMusicMark: UIImage? = UIImage(
        systemName: Podcast.withoutMusicSymbol,
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
    )?.withRenderingMode(.alwaysTemplate)

    // MARK: - Transport

    /// A row in a list is not a play/pause button. Tapping the thing that is
    /// already playing should take you to it - pausing from a list, with a
    /// glance and a moving car, is the last thing anyone means by that tap.
    /// Pause is on the Now Playing screen and on the wheel.
    private func openRadio() {
        switch engine.source {
        case .radio:
            if !engine.isPlaying { engine.resume() }
        default:
            if let url = AppConstants.fallbackStreamURL {
                engine.play(.radio(url: url))
            }
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

    /// It saves on the press. Anything that asks a follow-up question - a
    /// category, a confirmation - is a menu to read while driving, which is the
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
        // Its own key: the same Serbian word is also the name of the list,
        // and in English an acknowledgement and a list are different words.
        template.upNextTitle = justBookmarked
            ? String(localized: "carplay.bookmarked", defaultValue: "Zabeleženo")
            : String(localized: "Zabeleži")
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
            .sink { [weak self] _ in
                self?.refreshRadioItem()
                // Pausing is where the position stops moving, so it is the
                // last chance to write down where it stopped - the throttle
                // below can be up to fifteen seconds behind it.
                self?.refreshContinueItem()
            }
            .store(in: &cancellables)

        // Fifteen seconds, not every half second the observer fires: the row
        // is read when somebody comes back to the list, not while they stare
        // at it, and this costs one string assignment.
        engine.currentTimePublisher
            .throttle(for: .seconds(15), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.refreshContinueItem() }
            .store(in: &cancellables)

        engine.sourcePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshRadioItem()
                // What to carry on with has changed along with it.
                self?.radioTemplate?.updateSections(self?.radioSections() ?? [])
                // The button belongs to whatever is playing, so it comes and
                // goes with it rather than sitting there doing nothing.
                self?.refreshNowPlayingButtons()
            }
            .store(in: &cancellables)
    }

    /// The position on the carry-on row, while the episode it names is the
    /// one playing.
    ///
    /// The sections are rebuilt when the source changes and not otherwise, so
    /// through one long listen the row went on showing the second the car
    /// connected at - half an hour behind by the time anybody came back to
    /// the list. Tapping it was always right, because the handler resumes
    /// whatever is loaded rather than trusting the text; it was the text that
    /// lied, and it lied in the one shape that reads as the listen not having
    /// been saved.
    ///
    /// Only the string is rewritten. Rebuilding the sections would send the
    /// repository for the whole list every few seconds in a moving car, to
    /// change six characters.
    private func refreshContinueItem() {
        guard let continueItem, let podcast = continuePodcast else { return }
        // Not ours to update when something else is playing: the text then
        // comes from the store, and the store has not moved either.
        guard case .podcast(let playing) = engine.source, playing.id == podcast.id else { return }
        continueItem.setDetailText(continueDetail(for: podcast))
    }

    private func refreshRadioItem() {
        radioItem?.setDetailText(radioDetailText)
        if case .radio = engine.source {
            radioItem?.isPlaying = engine.isPlaying
        } else {
            radioItem?.isPlaying = false
        }
    }

    /// What the row says it will do, which is no longer "Zaustavi" - it
    /// stopped being able to stop anything.
    private var radioDetailText: String {
        if case .radio = engine.source {
            return engine.isPlaying ? String(localized: "Uživo") : String(localized: "Nastavi")
        }
        return String(localized: "Pusti")
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
    /// into a square - so the glyph came out stretched. Drawing it centred on
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
