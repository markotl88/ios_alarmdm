//
//  AppLanguage.swift
//  AlarmDM
//
//  Serbian unless the person says otherwise — whatever the phone is set to.
//

import Foundation

/// Which language the app speaks.
///
/// iOS picks from the phone's preferred languages, and almost every phone
/// lists English somewhere. So an app written in Serbian, for a Serbian radio
/// station, opened in Serbia, came up in English — an answer nobody asked
/// for, since the episodes, the shows and the station are all Serbian anyway.
/// English is here for the rare person who wants it, not as the default for
/// everyone whose phone happens to be set up in US English.
///
/// The way to say so is the one iOS uses itself: the per-app language lives in
/// the app's own defaults under `AppleLanguages`, and the Language row in
/// Settings reads and writes exactly that. Writing it once, on the first
/// launch, is the same as the person having chosen Serbian there — and their
/// own choice afterwards is never touched again.
enum AppLanguage {

    static let serbian = "sr-Latn"

    private enum Key {
        /// Apple's own, in this app's defaults domain.
        static let languages = "AppleLanguages"
        /// Ours, so that the line above is written exactly once ever.
        static let defaulted = "languageDefaultedToSerbian"
    }

    /// Called as early as this app runs any code of its own.
    ///
    /// The bundle's language was decided before that, so this launch may still
    /// be in the phone's language; every launch after it is Serbian. Picking
    /// English in Settings overwrites what was written here, and this never
    /// writes again.
    static func applyDefaultOnFirstLaunch(_ defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Key.defaulted) else { return }
        defaults.set(true, forKey: Key.defaulted)
        defaults.set([serbian, "en"], forKey: Key.languages)

        AppLog.write(.library, "language set to \(serbian) for the next launch")
    }

    /// What the app is speaking right now, in that language.
    static var currentName: String {
        let code = Bundle.main.preferredLocalizations.first ?? serbian
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
