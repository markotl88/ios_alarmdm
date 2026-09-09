//
//  CustomTabBarContainerView.swift
//  TestTabBar2
//
//  Created by Marko Stajic on 31.10.2024.
//
//
//import SwiftUI
//
//public struct CustomTabBarContainerView<Content: View> : View {
//    
//    @Binding var selection: TabBarItem
//    let content: Content
//    @State private var tabs: [TabBarItem] = []
//    @EnvironmentObject private var playerViewModel: PlayerViewModel
//
//    init(selection: Binding<TabBarItem>, @ViewBuilder content: () -> Content) {
//        self._selection = selection
//        self.content = content()
//    }
//    
//    public var body: some View {
//        ZStack(alignment: .bottom) {
//            content
//                .safeAreaInset(edge: .bottom) {
//                    CustomTabBarView(tabs: tabs, selection: $selection, localSelection: selection)
//                        .ignoresSafeArea(edges: .bottom)
//                }
//        }
//        .onPreferenceChange(TabBarItemsPreferenceKey.self) { value in
//            self.tabs = value
//        }
//    }
//}

//if !playerViewModel.isExpanded {
//    MiniPlayerView(playerOffset: 0, viewModel: playerViewModel)
//        .background(Color.white)
//        .clipShape(RoundedRectangle(cornerRadius: 10))
//        .shadow(radius: 4)
//        .frame(maxWidth: .infinity) // Full width
//        .frame(height: 60) // Adjust height as needed
//        .padding(.bottom, 10) // Additional padding to align precisely
//}

//    .overlay {
//        if let playerMode = playerViewModel.mode {
//            PlayerModalView(viewModel: playerViewModel, playerOffset: 0)
//                .background(Color.black.opacity(0.4))
//                .edgesIgnoringSafeArea(.all)
//        }
//    }
//

