//
//  MockPodcastService.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI

// Mock PodcastServiceProtocol
class MockPodcastService: PodcastServiceProtocol {
    func getPodcasts(page: Int?, completion: @escaping (Result<PaginationDataResponse<Podcast>, any Error>) -> Void) {
        let mockPodcasts = [
            Podcast(title: "Mock Podcast 1", subtitle: "Subtitle 1", timestamp: "", podcastUrl: "", duration: "", lengthInBytes: 0, itunesDuration: "", fileUrl: "", isFavorite: false, isDownloaded: false, withMusic: false, createdDate: nil),
            Podcast(title: "Mock Podcast 2", subtitle: "Subtitle 2", timestamp: "", podcastUrl: "", duration: "", lengthInBytes: 0, itunesDuration: "", fileUrl: "", isFavorite: false, isDownloaded: false, withMusic: false, createdDate: nil),
            Podcast(title: "Mock Podcast 3", subtitle: "Subtitle 3", timestamp: "", podcastUrl: "", duration: "", lengthInBytes: 0, itunesDuration: "", fileUrl: "", isFavorite: false, isDownloaded: false, withMusic: false, createdDate: nil)
        ]
        let mockPaginationDataResponse = PaginationDataResponse(page: 1, pageSize: 30, totalItems: 90, totalPages: 3, podcasts: mockPodcasts)
        completion(.success(mockPaginationDataResponse))
    }
}
