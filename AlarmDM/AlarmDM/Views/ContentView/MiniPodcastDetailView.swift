//
//  MiniPodcastDetailView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 21.10.2024.
//

import Foundation
import SwiftUI

struct MiniPlayerView: View {
    
    @ObservedObject var viewModel: PodcastDetailViewModel
    
    var body: some View {
        HStack {
            Image("icon_down") // Replace with actual podcast artwork
                .resizable()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading) {
                Text(viewModel.title)
                    .font(.headline)
                Text(viewModel.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Play/Pause Button
            Button(action: {
                viewModel.togglePlayPause()
            }) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .resizable()
                    .frame(width: 24, height: 24)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .onTapGesture {
            viewModel.isExpanded.toggle() // Expand to full-screen
        }
    }
}
