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
        // The Mac has no audio session to claim — the system mixes
        // applications on its own, and AVAudioSession does not exist there.
        #if !targetEnvironment(macCatalyst)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        // Here and not in a view: when the car starts the app there is no
        // phone window at all, and the listen still has to be written down.
        ListeningRecorder.shared.start()
        Analytics.start()
        return true
    }
}
