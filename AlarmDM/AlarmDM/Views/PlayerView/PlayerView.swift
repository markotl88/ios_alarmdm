//
//  PlayerView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 25.10.2024.
//

import SwiftUI

struct PlayerView: View {

    @StateObject var viewModel: PlayerViewModel
    var playerOffset: CGFloat

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

                Spacer()

                // Download/Delete Button with Circular Progress Indicator
                ZStack {
                    // Show the progress circle and the download icon only when downloading
                    if viewModel.isDownloading && !viewModel.showDeleteButton {
                        Circle()
                            .stroke(Color.gray, lineWidth: 5)
                            .opacity(0.3)
                            .frame(width: 50, height: 50)

                        Circle()
                            .trim(from: 0.0, to: CGFloat(viewModel.progress))
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 50, height: 50)
                            .animation(.linear, value: viewModel.progress)

                        Image(systemName: "arrow.down.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .foregroundColor(.primary)
                    }

                    // Show the animated green checkmark after the download is completed
                    if viewModel.showCheckmark && !viewModel.isDownloading {
                        ZStack {
                            Circle()
                                .fill(Color.green) // Green background for checkmark
                                .frame(width: 50, height: 50)
                            Image(systemName: "checkmark")
                                .resizable()
                                .foregroundColor(.white) // White checkmark
                                .scaledToFit()
                                .frame(width: 35, height: 35) // Thicker checkmark by increasing size
                                .transition(.scale)
                        }
                        .animation(.easeInOut)
                        .onAppear {
                            // Hide the checkmark after 1 second and show the delete button
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                withAnimation {
                                    viewModel.showCheckmark = false
                                    viewModel.showDeleteButton = true
                                }
                            }
                        }
                    }

                    // Show the delete button if the podcast is already downloaded or after the checkmark disappears
                    if viewModel.showDeleteButton {
                        Button(action: {
                            viewModel.deletePodcast()
                        }) {
                            Image(systemName: "trash.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.red)
                        }
                    } else if !viewModel.isDownloaded && !viewModel.isDownloading {
                        // Show the download button when not downloading or downloaded
                        Button(action: {
                            viewModel.downloadPodcast()
                        }) {
                            Image(systemName: "arrow.down.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.primary)
                        }
                    }
                }                .padding(.top, 10)

                Spacer()
            } else {
                // Mini player view
//                MiniPlayerView(playerOffset: playerOffset, viewModel: viewModel)
            }
        }
        .padding()
        .background(Color.white)
        .navigationTitle("Podcast Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.toggleDeleteButton()
        }
    }
}

