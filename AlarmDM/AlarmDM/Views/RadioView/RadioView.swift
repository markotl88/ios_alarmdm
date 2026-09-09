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

    var body: some View {
        List {
            // MARK: - Radio uživo
            Section(header: Text("Radio uživo")) {
                VStack(alignment: .leading, spacing: 12) {
                    Image("img_radio_wide")
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

                    Button {
                        playerViewModel.mode = .radio(stream: viewModel.livestreamUrl)
                        playerViewModel.togglePlayPause()
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Pusti uživo")
                        }
                        .font(.title2)
                        .foregroundColor(Color("primary"))
                        .padding(.top, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical)
            }

            // MARK: - Najnoviji podkasti
            Section(header: Text("Najnoviji podkasti")) {
                if viewModel.latestPodcasts.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.latestPodcasts, id: \.id) { podcast in
                        PodcastRowView(podcast: podcast)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                playerViewModel.mode = .podcast(podcast: podcast)
                                playerViewModel.togglePlayPause()
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Radio")
        .refreshable { viewModel.refresh() }
        .onAppear { viewModel.refresh() }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.isLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text("Učitavanje…").foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        } else if let error = viewModel.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text(error).font(.subheadline).foregroundColor(.secondary)
                Button("Pokušaj ponovo") { viewModel.refresh() }
                    .font(.subheadline)
            }
            .padding(.vertical, 8)
        } else {
            Text("Nema podkasta za prikaz.")
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
        }
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



