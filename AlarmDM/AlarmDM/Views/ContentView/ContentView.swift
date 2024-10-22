//
//  ContentView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI

struct ContentView: View {

    @StateObject private var viewModel: ContentViewModel
    @State private var currentViewModel: PodcastDetailViewModel? = nil

    init(viewModel: ContentViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            NavigationView {
                List {
                    ForEach(viewModel.podcasts) { podcast in
                        VStack(alignment: .leading) {
                            Text(podcast.title)
                                .font(.headline)
                            Text(podcast.subtitle)
                                .font(.subheadline)
                        }
                        .onTapGesture {
                            let detailViewModel = PodcastDetailViewModel(podcast: podcast)
                            currentViewModel = detailViewModel
                        }
                        .onAppear {
                            // Trigger fetching more data when this podcast appears
                            if podcast == viewModel.podcasts.last {
                                debugPrint("Content view: fetchDataIfNeeded")
                                viewModel.fetchDataIfNeeded(currentItem: podcast)
                            }
                        }
                    }

                    // Placeholder cells for loading
                    if viewModel.isLoadingMore {
                        ForEach(0..<5, id: \.self) { _ in
                            PlaceholderView()
                                .redacted(reason: .placeholder)
                                .shimmering() // Add blinking animation
                        }
                    }
                }
                .navigationTitle("Podcasts")
                .onAppear {
                    viewModel.fetchData()  // Initial fetch
                }
                .alert(isPresented: .constant(viewModel.errorMessage != nil)) {
                    Alert(title: Text("Error"), message: Text(viewModel.errorMessage ?? "Unknown error"), dismissButton: .default(Text("OK")))
                }
            }

            if let currentViewModel = currentViewModel {
                VStack {
                    Spacer()
                    MiniPlayerView(viewModel: currentViewModel)
                }
            }
        }
        .overlay(
            currentViewModel.map { viewModel in
                PodcastDetailModalView(viewModel: viewModel)
                    .background(Color.black.opacity(0.4))
                    .edgesIgnoringSafeArea(.all)
            }
        )
    }
}

struct PodcastDetailModalView: View {
    
    @ObservedObject var viewModel: PodcastDetailViewModel
    
    var body: some View {
        VStack {
            if viewModel.isExpanded {
                PodcastDetailView(viewModel: viewModel)
                    .transition(.move(edge: .bottom))
            }
            Spacer()
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    if value.translation.height > 100 {
                        // Instead of dismissing, toggle the isExpanded state
                        withAnimation {
                            viewModel.isExpanded.toggle()
                        }
                    }
                }
        )
    }
}

//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        let mockService = MockPodcastService()
//        let viewModel = ContentViewModel(podcastService: mockService)
//        ContentView(viewModel: viewModel)
//    }
//}

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
