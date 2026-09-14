//
//  AppConstants.swift
//  AlarmDM
//

import Foundation
import CryptoKit

enum AppConstants {
    /// Used when the livestream lookup fails, so the radio button always does something.
    static let fallbackStreamURL = URL(string: "https://stream.daskoimladja.com/proxy/daskomladja/stream")

    static let webshop = URL(string: "https://daskoimladja.bigcartel.com/")
    static let phoneNumber = "+38166442266"
    static let bankAccount = "325-9300600398707-66"
}

extension UUID {
    /// A UUID derived deterministically from a stable string — the episode's media URL.
    ///
    /// The API has no UUIDs, and `Podcast` previously generated a fresh one on every
    /// decode. Since that UUID was the episode's primary key, each refresh inserted
    /// the same episode again instead of updating it — and nothing written against one
    /// of those ids could ever be found again. Deriving the id from the feed keeps one
    /// row per episode across refreshes, across launches, and across devices.
    static func stable(from string: String) -> UUID {
        var bytes = Array(Insecure.MD5.hash(data: Data(string.utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5-ish: derived, not random
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
