//
//  RadioViewModel.swift
//  AlarmDM
//
//  Created by Marko Stajic on 24.10.2024.
//

import Foundation
import Combine

final class RadioViewModel: ObservableObject {
    
    @Published var livestreamUrl: URL?
    
    private let podcastService: PodcastServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(podcastService: PodcastServiceProtocol = PodcastService()) {
        self.podcastService = podcastService
        fetchLivestreamUrl()
    }
    
    // MARK: - Fetch Livestream URL
    private func fetchLivestreamUrl() {
        podcastService.getLivestream { [weak self] result in
            switch result {
            case .success(let url):
                DispatchQueue.main.async {
                    self?.livestreamUrl = url
                }
            case .failure(let error):
                print("Error fetching livestream URL: \(error.localizedDescription)")
            }
        }
    }
}
