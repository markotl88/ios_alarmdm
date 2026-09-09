//
//  RadioViewModel.swift
//  AlarmDM
//

import Foundation
import Combine

final class RadioViewModel: ObservableObject {

    @Published var livestreamUrl: URL?
    @Published var latestPodcasts: [Podcast] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let podcastService: PodcastServiceProtocol
    private let repository = PodcastRepository.shared

    init(podcastService: PodcastServiceProtocol = PodcastService()) {
        self.podcastService = podcastService
        fetchLivestreamUrl()
        loadCached()
    }

    /// Whatever is already on disk shows instantly; the network refresh follows.
    private func loadCached() {
        latestPodcasts = repository.latestPodcasts(limit: 20)
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        podcastService.getPodcasts(for: nil, page: 1, date: nil, isBefore: true) { [weak self] result in
            guard let self else { return }
            self.isLoading = false

            switch result {
            case .success(let page):
                self.repository.save(page.podcasts.map { Podcast(from: $0) })
                self.latestPodcasts = self.repository.latestPodcasts(limit: 20)
            case .failure(let error):
                if self.latestPodcasts.isEmpty {
                    self.errorMessage = "Nije moguće učitati podkaste. Proveri internet vezu."
                }
                debugPrint("Error fetching podcasts: \(error.localizedDescription)")
            }
        }
    }

    func toggleFavourite(_ podcast: Podcast) {
        EpisodeLibrary.shared.toggleFavourite(podcast)
        latestPodcasts = repository.latestPodcasts(limit: 20)
    }

    func deleteDownload(_ podcast: Podcast) {
        EpisodeLibrary.shared.deleteDownload(podcast)
        latestPodcasts = repository.latestPodcasts(limit: 20)
    }

    private func fetchLivestreamUrl() {
        podcastService.getLivestream { [weak self] result in
            switch result {
            case .success(let url):
                DispatchQueue.main.async { self?.livestreamUrl = url }
            case .failure(let error):
                debugPrint("Error fetching livestream URL: \(error.localizedDescription)")
            }
        }
    }
}
