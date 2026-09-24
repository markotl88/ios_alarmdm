//
//  ShowView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 22.10.2024.
//

import SwiftUI

struct ShowView: View {
    @Environment(\.horizontalSizeClass) private var widthClass

    var body: some View {
        ShowListView()
            .navigationTitle(widthClass == .regular ? Text(verbatim: "") : Text("Emisije"))
            .navigationBarTitleDisplayMode(widthClass == .regular ? .inline : .automatic)
    }
}

/// The order is fixed in `Show.featured`; everything else falls under Arhiva.
struct ShowListView: View {
    @Environment(\.horizontalSizeClass) private var widthClass

    var body: some View {
        List {
            if widthClass == .regular {
                Section {
                    Text("Emisije")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listSectionSpacing(12)
            }

            Section {
                ForEach(Show.featured, id: \.self) { show in
                    NavigationLink(destination: PodcastEpisodesView(show: show)) {
                        ShowRowView(show: show)
                    }
                }
            }

            if !Show.archived.isEmpty {
                Section("Arhiva") {
                    ForEach(Show.archived, id: \.self) { show in
                        NavigationLink(destination: PodcastEpisodesView(show: show)) {
                            ShowRowView(show: show)
                        }
                    }
                }
            }
        }
    }
}
struct ShowRowView: View {
    let show: Show

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Show Image
            Image(show.imageName)
                .resizable()
                .frame(width: 80, height: 80)
                .cornerRadius(10)
                .padding(.vertical, 8)
            
            // Text Content (Title and Description)
            VStack(alignment: .leading, spacing: 8) {
                Text(show.displayName)
                    .font(.headline)
                    .foregroundColor(Color("primaryText"))
                
                Text(show.description)
                    .font(.subheadline)
                    .foregroundColor(Color("secondaryText"))
                    .lineLimit(3)
            }
            
            Spacer() // Push content to the left
        }
        .padding(.vertical, 4)
    }
}
