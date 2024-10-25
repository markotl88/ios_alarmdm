//
//  PodcastDetailModalView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 24.10.2024.
//

import SwiftUI

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
