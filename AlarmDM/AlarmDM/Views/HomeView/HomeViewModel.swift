//
//  HomeViewModel.swift
//  AlarmDM
//
//  Created by Marko Stajic on 24.10.2024.
//

import SwiftUI

class HomeViewModel: ObservableObject {
    @Published var selectedSegment: Int = 0 // 0 for RadioView, 1 for PodcastEpisodesView
    
    init() {
        // Initialization if needed
    }
    
    // Add additional business logic if necessary
}
