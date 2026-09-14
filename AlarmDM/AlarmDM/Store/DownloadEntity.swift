//
//  DownloadEntity.swift
//  AlarmDM
//
//  Which episodes have a file on this device. Local by nature: the file is
//  here and nowhere else.
//

import Foundation
import SwiftData

/// A downloaded episode's file name, kept out of the synced store on purpose.
/// A path is a fact about one device, and syncing it would have the iPad
/// claiming an episode is downloaded because the phone downloaded it.
@Model
final class DownloadEntity {

    var podcastId: UUID = UUID()
    var fileName: String = ""
    var downloadedAt: Date = Date()

    init(podcastId: UUID, fileName: String) {
        self.podcastId = podcastId
        self.fileName = fileName
    }
}
