//
//  RadioView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI

struct RadioView: View {
    var body: some View {
        VStack {
            Text("Radio uživo")
                .font(.title)
                .padding()
            Text("ALARM sa Daškom i Mlađom, svakog radnog dana 07-10h. Dobra muzika non-stop!")
                .padding()
            Spacer()
            // Add other components like play button, volume slider, etc.
            HStack {
                Button(action: {
                    // Play action
                }) {
                    Image(systemName: "play.circle.fill")
                        .font(.largeTitle)
                }
                Button(action: {
                    // Stop action
                }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.largeTitle)
                }
            }
            .padding()
            Slider(value: .constant(0.5))
                .padding()
            Spacer()
        }
        .padding()
    }
}

struct ContactView: View {
    var body: some View {
        Text("Contact View")
    }
}

struct StoreView: View {
    var body: some View {
        Text("Store View")
    }
}

struct SettingsView: View {
    var body: some View {
        Text("Settings View")
    }
}

#Preview {
    StoreView()
}

