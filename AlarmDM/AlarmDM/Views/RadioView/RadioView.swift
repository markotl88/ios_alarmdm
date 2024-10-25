//
//  RadioView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI

struct RadioView: View {
    @StateObject private var viewModel = RadioViewModel()
    @State private var currentViewModel: PodcastDetailViewModel? = nil

    var body: some View {
        VStack {
            Text("Radio uživo")
                .font(.title)
                .padding()
            
            Text("ALARM sa Daškom i Mlađom, svakog radnog dana 07-10h. Dobra muzika non-stop!")
                .padding()
            
            Spacer()
            
            HStack {
                Button(action: {
                    debugPrint("Play")
                    let detailViewModel = PodcastDetailViewModel(podcastId: nil, onlineStream: viewModel.livestreamUrl)
                    currentViewModel = detailViewModel
                }) {
                    Image(systemName: "play.circle.fill")
                        .font(.largeTitle)
                }
            }
            .padding()
            
            Spacer()
            
            if let currentViewModel = currentViewModel {
                VStack {
                    Spacer()
                    MiniPlayerView(viewModel: currentViewModel)
                }
            }
        }
        .padding()
        .overlay(
            currentViewModel.map { viewModel in
                PodcastDetailModalView(viewModel: viewModel)
                    .background(Color.black.opacity(0.4))
                    .edgesIgnoringSafeArea(.all)
            }
        )
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

