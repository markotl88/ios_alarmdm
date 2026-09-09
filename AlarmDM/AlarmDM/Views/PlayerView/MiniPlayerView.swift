//
//  MiniPlayerView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 25.10.2024.
//

import Foundation
import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        Rectangle()
            .fill(Color.orange)
            .frame(height: 60)
            .overlay(
                HStack {
                    Text("Now Playing")
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        playerViewModel.isPresented = false
                    }) {
                        Image(systemName: "stop.fill")
                            .foregroundColor(.white)
                    }
                    Button(action: {
                        withAnimation {
                            playerViewModel.isExpanded = true
                        }
                    }) {
                        Image(systemName: "chevron.up")
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal)
            )
    }
}

struct FullscreenPlayerView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @State private var offset: CGFloat = 0

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    withAnimation {
                        playerViewModel.isExpanded = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                }
            }

            Spacer()
            Text("Full Screen Player")
                .font(.largeTitle)
                .foregroundColor(.white)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.orange)
        .offset(y: offset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        offset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        withAnimation {
                            playerViewModel.isExpanded = false
                        }
                    }
                    withAnimation {
                        offset = 0
                    }
                }
        )
        .ignoresSafeArea()
    }
}

/* struct MiniPlayerView: View {
    
    var playerOffset: CGFloat
    @ObservedObject var viewModel: PlayerViewModel
    
    var body: some View {
        VStack {
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
}
*/
