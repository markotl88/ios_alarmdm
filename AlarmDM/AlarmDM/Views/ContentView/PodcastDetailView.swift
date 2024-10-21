//
//  PodcastDetailView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 21.10.2024.
//
import SwiftUI

struct PodcastDetailView: View {
    
    @ObservedObject var viewModel: PodcastDetailViewModel
    
    var body: some View {
        VStack {
            if viewModel.isExpanded {
                Spacer()
                
                // Full-screen player view
                Image("icon_down")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                Text(viewModel.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top, 20)
                
                Text(viewModel.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.top, 5)
                
                Spacer()
                
                // Play/Pause Button
                Button(action: {
                    viewModel.togglePlayPause()
                }) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.primary)
                }
                .padding(.bottom, 20)
                
                // Progress Slider
                Slider(value: $viewModel.progress, in: 0...1)
                    .padding(.horizontal)
                
                // Duration
                HStack {
                    Text("0:00")
                    Spacer()
                    Text("2:50:36") // Replace with actual duration if available
                }
                .padding(.horizontal)
                .foregroundColor(.gray)
                
                Spacer()
            } else {
                // Mini player view
                MiniPlayerView(viewModel: viewModel)
            }
        }
        .padding()
        .background(Color.white)  // <-- Set a solid background color
        .navigationTitle("Podcast Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
