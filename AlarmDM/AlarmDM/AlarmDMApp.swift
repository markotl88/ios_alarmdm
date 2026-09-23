//
//  AlarmDMApp.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI

@main
struct AlarmDMApp: SwiftUI.App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                // Only ever different from the phone's on the first launch -
                // see AppLanguage.
                .environment(\.locale, AppLanguage.localeForThisLaunch)
        }
        #if targetEnvironment(macCatalyst)
        // Closing the window no longer quits the app, which is the point: the
        // radio carries on, driven from Now Playing in the menu bar and the
        // media keys, and a click on the Dock icon brings the window back.
        //
        // Supporting that is what makes a second window possible, and one
        // player has no use for two. File › New Window goes.
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }
}
