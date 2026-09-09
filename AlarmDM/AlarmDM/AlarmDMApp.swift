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
            NewTabContentView()
        }
    }

    // MARK: - Initializers

    init() {
        setupRealm()
    }
    
    // MARK: - Private methods
    
    private func setupRealm() {
        // Set up Realm configuration with schema version and migration block if needed
        let config = Realm.Configuration(
            schemaVersion: 2, // Increment this when making changes to the Realm schema
            migrationBlock: { migration, oldSchemaVersion in
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
