//
//  AppDelegate.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.04.2025.
//
import UIKit
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // The Mac has no audio session to claim - the system mixes
        // applications on its own, and AVAudioSession does not exist there.
        //
        // The category says what this app is for, which is worth saying
        // before anything can be played. The session itself is not claimed
        // here: claiming it at launch takes the sound away from whatever the
        // person was already listening to, before they have pressed anything
        // in this app. PlaybackEngine claims it when something starts, and
        // this mode is the one it uses.
        #if !targetEnvironment(macCatalyst)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        #endif

        // Here and not in a view: when the car starts the app there is no
        // phone window at all, and the listen still has to be written down.
        // Before anything is drawn, and it takes effect from the next launch
        // - see AppLanguage.
        AppLanguage.applyDefaultOnFirstLaunch()

        ListeningRecorder.shared.start()
        Analytics.start()
        return true
    }
}
