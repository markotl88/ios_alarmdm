//
//  ShowView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 22.10.2024.
//

import SwiftUI

struct ShowView: View {
    @StateObject private var viewModel = ShowViewModel()
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    
    var body: some View {
        ShowListView(shows: viewModel.shows)
            .navigationTitle("Emisije")
            .background(Color("background").edgesIgnoringSafeArea(.all))
    }
}
struct ShowListView: View {
    let shows: [Show]
    @EnvironmentObject private var playerViewModel: PlayerViewModel

    var body: some View {
        List(shows, id: \.self) { show in
            NavigationLink(destination: PodcastEpisodesView(show: show)) {
                ShowRowView(show: show)
                    .listRowBackground(Color("background")) // List row background color
            }
        }
        .background(Color("background")) // Overall background
    }
}
struct ShowRowView: View {
    let show: Show
    @EnvironmentObject private var playerViewModel: PlayerViewModel

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
                    .foregroundColor(Color("primaryText")) // Text color from assets
                
                Text(show.description)
                    .font(.subheadline)
                    .foregroundColor(Color("secondaryText")) // Secondary text color from assets
                    .lineLimit(3)
            }
            
            Spacer() // Push content to the left
        }
        .background(Color("primary").opacity(0.05)) // Light background for the row
        .cornerRadius(8)
        .padding(.vertical, 4)
    }
}
