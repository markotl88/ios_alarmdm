//
//  RadioView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI

struct RadioView: View {
    @StateObject private var viewModel = RadioViewModel()
    @EnvironmentObject private var playerViewModel: PlayerViewModel

    private let calendar = Calendar.current

    var body: some View {
        List {
            // MARK: - Radio uživo sekcija
            Section(header: Text("Radio uživo")) {
                VStack(alignment: .leading, spacing: 12) {
                    Image("iTunesArtwork") // ← tvoja hardkodovana slika
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 180)
                        .clipped()
                        .cornerRadius(12)

                    Text("ALARM sa Daškom i Mlađom")
                        .font(.headline)

                    Text("Svakog radnog dana 07-10h. Dobra muzika non-stop!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button(action: {
                        debugPrint("Play radio stream")
                        playerViewModel.mode = .radio(stream: viewModel.livestreamUrl)
                        playerViewModel.togglePlayPause()
                    }) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Pusti uživo")
                        }
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .padding(.top, 8)
                    }
                }
                .padding(.vertical)
            }

            // MARK: - Podcasti sekcija
            Section(header: Text("Najnoviji podkasti")) {
                ForEach(latestPodcasts(), id: \.id) { podcast in
                    HStack(spacing: 12) {
                        Image(podcast.show.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(podcast.title)
                                .font(.headline)
                            Text(podcast.subtitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                    .onTapGesture {
                        playerViewModel.mode = .podcast(podcast: podcast)
                        playerViewModel.togglePlayPause()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Radio")
    }

    private func latestPodcasts() -> [Podcast] {
        let all = PodcastRepository.shared.latestPodcasts(limit: 100)
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return all.filter { ($0.createdDate ?? .distantPast) > oneMonthAgo }
    }
}
/*
struct RadioView: View {
    @StateObject private var viewModel = RadioViewModel()
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    
    var body: some View {
        GeometryReader { proxy in
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
                        playerViewModel.mode = .radio(stream: viewModel.livestreamUrl)
                    }) {
                        Image(systemName: "play.circle.fill")
                            .font(.largeTitle)
                    }
                }
                .padding()
                
                Spacer()
            }
            .preference(key: InnerContentSize.self, value: [proxy.frame(in: CoordinateSpace.global)])
            .padding()
        }
    }
}
 */

struct ContactView: View {
    var body: some View {
        Color.orange.opacity(0.5)
        Text("Contact View")
    }
}

struct StoreView: View {
    var body: some View {
        Color.green.opacity(0.5)
        Text("Store View")
    }
}

struct SettingsView: View {
    var body: some View {
        Color.yellow.opacity(0.5)
        Text("Settings View")
    }
}

#Preview {
    StoreView()
}

