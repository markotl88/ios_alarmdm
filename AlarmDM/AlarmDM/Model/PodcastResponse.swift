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
    var fileUrl = ""
    var createdDate: String = ""
}
