//
//  PodcastResponse.swift
//  AlarmDM
//
//  Created by Marko Stajic on 22.10.2024.
//

import Foundation

struct PodcastResponse: Codable {
    var id: String = ""
    var title = ""
    var subtitle = ""
    var timestamp: String?
    var podcastUrl = ""
    var duration = ""
    var lengthInBytes = 0.0
    var itunesDuration = ""
    var createdDate: String = ""
    /// When the episode went out live, worked out by the Cloud Function from
    /// the publish time and the running time. Null for the music-free cut,
    /// whose running time no longer matches the clock.
    var airedAt: String?
    var showType: String?
    var withMusic: Bool = false
    /// How long the closing credits run, in seconds. Zero or absent means the
    /// show has not been measured - not that it ends without one.
    var outroSeconds: Double?
}
