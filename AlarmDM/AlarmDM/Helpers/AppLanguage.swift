//
//  AppLanguage.swift
//  AlarmDM
//
//  Serbian unless the person says otherwise - whatever the phone is set to.
//

import Foundation
import ObjectiveC

/// Which language the app speaks.
///
/// iOS picks from the phone's preferred languages, and almost every phone
/// lists English somewhere. So an app written in Serbian, for a Serbian radio
/// station, opened in Serbia, came up in English - an answer nobody asked
/// for, since the episodes, the shows and the station are all Serbian anyway.
/// English is here for the rare person who wants it, not as the default for
/// everyone whose phone happens to be set up in US English.
///
/// The way to say so is the one iOS uses itself: the per-app language lives in
/// the app's own defaults under `AppleLanguages`, and the Language row in
/// Settings reads and writes exactly that. Writing it once, on the first
/// launch, is the same as the person having chosen Serbian there - and their
/// own choice afterwards is never touched again.
enum AppLanguage {

    static let serbian = "sr-Latn"

    /// True for the launch that wrote the default, and only that one. The
    /// views ask, because SwiftUI does not take the answer from the bundle.
    private(set) static var isForcingThisLaunch = false

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
        speakSerbianForThisLaunch()

        AppLog.write(.library, "language set to \(serbian)")
    }

    /// The line above takes effect at the next launch, and this one is about
    /// the launch happening now - the first one, where an app in Serbian for a
    /// Serbian station would otherwise introduce itself in English and only
    /// get it right the second time anybody opened it.
    ///
    /// Every string the app looks up goes through Bundle.main, so Bundle.main
    /// is given a subclass that looks them up in the Serbian folder instead.
    /// It is a blunt instrument and it is used exactly once, on the launch
    /// that writes the default: from the second launch the bundle is Serbian
    /// on its own, and anyone who later picks English in Settings is never
    /// touched, because this never runs again.
    ///
    /// What it cannot move is the text iOS itself supplies - the share sheet,
    /// system alerts - which stays in the phone's language for this one
    /// launch. And if a future iOS stops resolving strings this way, nothing
    /// breaks: the launch is in the phone's language, exactly as before.
    private static func speakSerbianForThisLaunch() {
        guard Bundle.main.preferredLocalizations.first != serbian else { return }

        isForcingThisLaunch = true

        AppLog.write(.library, "forcing \(serbian) for this launch - bundle has \(Bundle.main.localizations), prefers \(Bundle.main.preferredLocalizations)")

        guard let path = Bundle.main.path(forResource: serbian, ofType: "lproj"),
              let serbianBundle = Bundle(path: path) else {
            AppLog.write(.library, "no \(serbian).lproj in the bundle")
            return
        }

        #if DEBUG
        // The key in the catalog is the Serbian text itself, so a lookup that
        // resolves to English answers "Live radio" and one that stays Serbian
        // answers "Radio uzivo". Which of the two comes back after the swap
        // is the whole question about the class below.
        let beforeSwap = String(localized: "Radio uživo")
        #endif

        LanguageBundle.strings = serbianBundle
        object_setClass(Bundle.main, LanguageBundle.self)

        #if DEBUG
        AppLog.write(.library, "lookup in code: '\(beforeSwap)' before the bundle swap, '\(String(localized: "Radio uživo"))' after")
        #endif
    }

    /// What the views are given. SwiftUI resolves a literal against the
    /// locale in the environment, which is the one lever that reaches the
    /// text on screen - the bundle above does not reach it, as one launch in
    /// English proved.
    static var localeForThisLaunch: Locale {
        isForcingThisLaunch ? Locale(identifier: serbian) : .current
    }

    /// What the app is speaking right now, in that language.
    static var currentName: String {
        let code = Bundle.main.preferredLocalizations.first ?? serbian
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// Bundle.main wearing this class answers every lookup from one language's
/// folder. See AppLanguage.speakSerbianForThisLaunch.
private final class LanguageBundle: Bundle, @unchecked Sendable {

    static var strings: Bundle?

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        LanguageBundle.strings?.localizedString(forKey: key, value: value, table: tableName)
            ?? super.localizedString(forKey: key, value: value, table: tableName)
    }
}
