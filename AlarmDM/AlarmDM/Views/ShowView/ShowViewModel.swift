//
//  ShowViewModel.swift
//  AlarmDM
//

import SwiftUI

final class ShowViewModel: ObservableObject {
    /// Ordered by how recently the show aired, measured against the full feed
    /// (5252 episodes) in September 2026. `mozemoSamoDaSeSlikamo` was dropped:
    /// it has no episodes anywhere in the feed, so its screen was always empty.
    @Published var shows: [Show] = Show.listed
}
