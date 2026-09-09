//
//  PodcastEpisodesView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI

struct PodcastEpisodesView: View {
    
    @ObservedObject var viewModel: PodcastEpisodesViewModel
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    
    var body: some View {
        ZStack {
            podcastList
        }
    }
    
    // Extracted the List into a computed property
    private var podcastList: some View {
        List {
            ForEach(viewModel.podcasts) { podcast in
                PodcastRowView(podcast: podcast)
                    .onTapGesture {
                        print("Do nothing")
//                        playerViewModel.mode = .podcast(podcast: podcast)
//                        playerViewModel.isPresented = true
                    }
                    .onAppear {
                        // Trigger fetching more data when this podcast appears
                        if podcast == viewModel.podcasts.last {
                            viewModel.fetchDataIfNeeded(currentItem: podcast)
                        }
                    }
            }
            
            // Show placeholder cells for loading if there is more data to fetch
//            if viewModel.isLoadingMore && viewModel.hasMoreData {
//                ForEach(0..<5, id: \.self) { _ in
//                    PlaceholderView()
//                        .redacted(reason: .placeholder)
//                        .shimmering() // Add blinking animation
//                }
//            }
        }
        .navigationTitle("Podcasts")
        .onAppear {
            viewModel.fetchData()  // Initial fetch
        }
        .alert(isPresented: .constant(viewModel.errorMessage != nil)) {
            Alert(title: Text("Error"), message: Text(viewModel.errorMessage ?? "Unknown error"), dismissButton: .default(Text("OK")))
        }
    }
}

// Separate View for each podcast row
struct PodcastRowView: View {
    let podcast: Podcast
    
    var body: some View {
        HStack {
            Image(podcast.show.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 50, height: 50)
                .cornerRadius(8)

            VStack(alignment: .leading) {
                Text(podcast.title)
                    .font(.headline)
                Text(podcast.subtitle)
                    .font(.subheadline)
            }
        }
    }
}

struct PlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 20)
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 20)
        }
        .padding()
    }
}

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Color.white
                    .mask(
                        Rectangle()
                            .fill(
                                LinearGradient(gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0), location: phase),
                                    .init(color: Color.white.opacity(0.5), location: phase + 0.1),
                                    .init(color: Color.white.opacity(0), location: phase + 0.2)
                                ]), startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .rotationEffect(.degrees(30))
                    )
                    .animation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false), value: phase)
            )
            .onAppear {
                phase = -0.5
                DispatchQueue.main.async {
                    withAnimation {
                        phase = 1.5
                    }
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        self.modifier(ShimmerEffect())
    }
}
