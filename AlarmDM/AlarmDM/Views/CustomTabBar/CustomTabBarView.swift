//
//  CustomTabBarView.swift
//  TestTabBar2
//
//  Created by Marko Stajic on 31.10.2024.
//

import SwiftUI

//struct CustomTabBarView: View {
//    
//    let tabs: [TabBarItem]
//    @Binding var selection: TabBarItem
//    @Namespace var animation
//    @State var localSelection: TabBarItem
//    
//    var body: some View {
//        // Log IDs for debugging        
//        tabBarVersion
//            .onChange(of: selection, { oldValue, newValue in
//                withAnimation(.easeInOut) {
//                    localSelection = newValue
//                }
//            })
//    }
//}
//
//extension CustomTabBarView {
//    
//    private var tabBarVersion: some View {
//        HStack {
//            ForEach(tabs, id: \.self) { tab in
//                tabView(tab: tab)
//                    .onTapGesture {
//                        switchToTab(tab: tab)
//                    }
//            }
//        }
//        .padding(6)
//        .background(Color.white.ignoresSafeArea(edges: .bottom))
//    }
//    
//    private func tabView(tab: TabBarItem) -> some View {
//        VStack {
//            Image(systemName: tab.iconName)
//                .font(.subheadline)
//            Text(tab.title)
//                .font(.caption)
//        }
//        .foregroundStyle(localSelection == tab ? tab.color : Color.gray)
//        .padding(.vertical, 8)
//        .frame(maxWidth: .infinity)
//        .background(
//            ZStack {
//                if localSelection == tab {
//                    RoundedRectangle(cornerRadius: 10)
//                        .fill(tab.color.opacity(0.2))
//                        .matchedGeometryEffect(id: "background_rectangle", in: animation)
//                }
//            }
//        )
//    }
//
//    private func  switchToTab(tab: TabBarItem) {
//        selection = tab
//    }
//}
