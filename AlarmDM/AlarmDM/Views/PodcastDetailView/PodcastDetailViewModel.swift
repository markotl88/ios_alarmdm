//
//  PodcastDetailViewModel.swift
//  AlarmDM
//
//  Created by Marko Stajic on 21.10.2024.
//

import Foundation
import Combine

import Foundation

class PodcastDetailViewModel: ObservableObject, Identifiable {
    
    let id = UUID() // This makes the view model identifiable
    
    @Published var title: String
    @Published var subtitle: String
    @Published var isPlaying = false
    @Published var progress: Double = 0.0
    @Published var isExpanded = true // Tracks whether the player is full-screen or minimized
    
    private let podcast: Podcast
    
    init(podcast: Podcast) {
        self.podcast = podcast
        self.title = podcast.title
        self.subtitle = podcast.subtitle
    }
    
    func togglePlayPause() {
        isPlaying.toggle()
    }
}
