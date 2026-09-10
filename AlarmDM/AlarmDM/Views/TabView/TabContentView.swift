//
//  TabView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 29.07.2024.
//

import SwiftUI

struct InnerContentSize: PreferenceKey {
  typealias Value = [CGRect]

  static var defaultValue: [CGRect] = []
  static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
    value.append(contentsOf: nextValue())
  }
}

struct NewTabContentView: View {
    @State private var currentItem: TabBarItem = .radio
    @StateObject private var playerViewModel = PlayerViewModel(mode: nil)

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                switch currentItem {
                case .radio:
                    NavigationStack {
                        RadioView()
                    }
                case .shows:
                    NavigationStack {
                        ShowView()
                    }
                case .support:
                    NavigationStack {
                        SupportView()
                    }
                case .settings:
                    NavigationStack {
                        SettingsView()
                    }
                }

                // rezerviši prostor za MiniPlayer + TabBar
                Spacer().frame(height: playerViewModel.isPresented && !playerViewModel.isExpanded ? 60 : 0)
                Spacer().frame(height: 60) // fiksna visina lažnog tab bara
            }

            VStack(spacing: 0) {
                Spacer()

                if playerViewModel.isPresented && !playerViewModel.isExpanded {
                    MiniPlayerView()
                        .environmentObject(playerViewModel)
                }
                
                if !playerViewModel.isExpanded {
                    TabBar(currentItem: $currentItem)
                }
            }

            if playerViewModel.isExpanded {
                FullscreenPlayerView()
                    .environmentObject(playerViewModel)
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: playerViewModel.isExpanded)
        .environmentObject(playerViewModel)
    }
}

import SwiftUI

//enum TabPage {
//    case radio, shows, support, settings
//}

struct TabBar: View {
    @Binding var currentItem: TabBarItem

    var body: some View {
        HStack {
            tabButton(item: .radio)
            Spacer()
            tabButton(item: .shows)
            Spacer()
            tabButton(item: .support)
            Spacer()
            tabButton(item: .settings)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color(UIColor.systemBackground).ignoresSafeArea(edges: .bottom))
        .foregroundColor(Color.primary)
        .font(.footnote)
    }

    @ViewBuilder
    private func tabButton(item: TabBarItem) -> some View {
        Button(action: {
            currentItem = item
        }) {
            VStack(spacing: 4) {
                Image(systemName: item.iconName)
                    .font(.system(size: 20, weight: currentItem == item ? .semibold : .regular))
                Text(item.title)
            }
            .foregroundColor(currentItem == item ? Color.accentColor : Color.secondary)
        }
    }
}

//struct TabBar: View {
//    @Binding var currentPage: TabPage
//
//    var body: some View {
//        HStack {
//            Button(action: { currentPage = .main }) {
//                VStack {
//                    Image(systemName: "house")
//                    Text("Home")
//                }
//            }
//            Spacer()
//            Button(action: { currentPage = .secondary }) {
//                VStack {
//                    Image(systemName: "car")
//                    Text("Secondary")
//                }
//            }
//        }
//        .padding()
//        .frame(height: 60)
//        .background(Color.black)
//        .foregroundColor(.white)
//    }
//}

struct TabContentView: View {
    @State private var selectedTab = 0
    @StateObject private var playerViewModel = PlayerViewModel(mode: nil)
    @State private var tabBarHeight: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    RadioView()
                }
                .tabItem {
                    Label("Radio", systemImage: "dot.radiowaves.left.and.right")
                }
                .tag(0)

                NavigationStack {
                    ShowView()
                }
                .tabItem {
                    Label("Shows", systemImage: "music.note.list")
                }
                .tag(1)

                NavigationStack {
                    SupportView()
                }
                .tabItem {
                    Label("Support", systemImage: "heart")
                }
                .tag(2)

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(3)
            }

            // 🟨 MINI PLAYER — ispod sadržaja, iznad tab bara
            Color.clear
                .frame(height: 0)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: TabBarHeightKey.self, value: proxy.safeAreaInsets.bottom)
                    }
                )

            if playerViewModel.isPresented {
                MiniPlayerView()
                    .environmentObject(playerViewModel)
                    .padding(.horizontal)
                    .padding(.bottom, tabBarHeight)
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
        }
        .onPreferenceChange(TabBarHeightKey.self) { self.tabBarHeight = $0 }
        .environmentObject(playerViewModel)
    }
}

struct TabBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
