//
//  PlayerModalView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 25.10.2024.
//

import SwiftUI

struct PlayerModalView: View {
    
    @ObservedObject var viewModel: PlayerViewModel
    var playerOffset: CGFloat

    var body: some View {
        VStack {
            if viewModel.isExpanded {
                PlayerView(viewModel: viewModel, playerOffset: playerOffset)
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
