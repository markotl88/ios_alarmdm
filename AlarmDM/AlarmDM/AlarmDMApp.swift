//
//  AlarmDMApp.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI
import RealmSwift

@main
struct AlarmDMApp: SwiftUI.App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Public properties
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }

    // MARK: - Initializers

    init() {
        setupRealm()
        // Realm is still the live database; this only carries favourites and
        // downloads across so they are waiting once the store takes over.
        RealmImport.runIfNeeded()
    }
    
    // MARK: - Private methods
    
    private func setupRealm() {
        // Set up Realm configuration with schema version and migration block if needed
        let config = Realm.Configuration(
            schemaVersion: 4, // Increment this when making changes to the Realm schema
            migrationBlock: { migration, oldSchemaVersion in
                if oldSchemaVersion < 4 {
                    // A bookmark's Double is a position in the episode, not a
                    // length. Renamed rather than added and copied, so any row
                    // written by a development build keeps its value.
                    migration.renameProperty(onType: BookmarkRealm.className(),
                                             from: "duration", to: "position")
                }
                if oldSchemaVersion < 3 {
                    // Provizorni podnevni program turned out to be Unutrašnja
                    // emigracija under an older name. Rows cached before the
                    // backend was updated still carry the retired key.
                    migration.enumerateObjects(ofType: PodcastRealm.className()) { _, newObject in
                        if newObject?["show"] as? String == "provizorniPodnevniProgram" {
                            newObject?["show"] = "unutrasnjaEmigracija"
                        }
                    }
                }
                if oldSchemaVersion < 2 {
                    // Episode ids used to be random UUIDs regenerated on every fetch, so
                    // older databases hold duplicate rows keyed by ids that no longer
                    // match anything. Clear them; the list refills from the API on launch.
                    migration.deleteData(forType: PodcastRealm.className())
                    migration.deleteData(forType: BookmarkRealm.className())
                }
            }
        )
        
        // Set the default Realm configuration
        Realm.Configuration.defaultConfiguration = config
        
        // Initialize Realm to ensure it's set up correctly
        do {
            _ = try Realm()
            print("Realm initialized successfully.")
        } catch {
            print("Failed to initialize Realm: \(error.localizedDescription)")
        }
    }
}
