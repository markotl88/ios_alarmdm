//
//  ShowView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 22.10.2024.
//

import SwiftUI

struct ShowView: View {
    @StateObject private var viewModel = ShowViewModel()

    var body: some View {
        ShowListView(shows: viewModel.shows)
            .navigationTitle("Emisije")
    }
}
struct ShowListView: View {
    let shows: [Show]

    var body: some View {
        List(shows, id: \.self) { show in
            NavigationLink(destination: PodcastEpisodesView(show: show)) {
                ShowRowView(show: show)
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
