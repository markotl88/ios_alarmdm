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
    
    // MARK: - Public properties
    
    var body: some Scene {
        WindowGroup {
            TabContentView()
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
            schemaVersion: 1, // Increment this when making changes to the Realm schema
            migrationBlock: { migration, oldSchemaVersion in
                if oldSchemaVersion < 1 {
                    // Perform necessary migration steps if needed
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
