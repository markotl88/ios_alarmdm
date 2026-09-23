//
//  AppSettings.swift
//  AlarmDM
//
//  The few preferences that change how the app behaves. Anything cosmetic
//  belongs in the view that draws it.
//

import SwiftUI

final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private enum Key {
        static let downloadsOverWiFiOnly = "downloadsOverWiFiOnly"
        static let suppressesUsageStatistics = "suppressesUsageStatistics"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// On by default. An hour of radio is a few megabytes; a back catalogue of
    /// episodes on a metered plan is real money — and the person who finds out
    /// afterwards is the one who paid for it. `object(forKey:)` rather than
    /// `bool(forKey:)`: an unset key has to read as true, not as false.
    var downloadsOverWiFiOnly: Bool {
        get { defaults.object(forKey: Key.downloadsOverWiFiOnly) as? Bool ?? true }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.downloadsOverWiFiOnly)
        }
    }

    var downloadsOverWiFiOnlyBinding: Binding<Bool> {
        Binding(
            get: { self.downloadsOverWiFiOnly },
            set: { self.downloadsOverWiFiOnly = $0 }
        )
    }

    /// Off by default, which means the counts are sent: they carry no
    /// identifier and describe nobody, and asking everyone to opt in to a
    /// count of button presses buys a worse answer and an extra screen. The
    /// switch is there for whoever would rather send nothing at all.
    var suppressesUsageStatistics: Bool {
        get { defaults.bool(forKey: Key.suppressesUsageStatistics) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.suppressesUsageStatistics)
        }
    }

    var suppressesUsageStatisticsBinding: Binding<Bool> {
        Binding(
            get: { self.suppressesUsageStatistics },
            set: { self.suppressesUsageStatistics = $0 }
        )
    }
}
