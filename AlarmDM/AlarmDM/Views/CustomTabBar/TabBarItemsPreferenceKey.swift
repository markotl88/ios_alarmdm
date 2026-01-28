//
//  TabBarItemsPreferenceKey.swift
//  TestTabBar2
//
//  Created by Marko Stajic on 31.10.2024.
//

import Foundation
import SwiftUI

struct TabBarItemsPreferenceKey : PreferenceKey {
    static var defaultValue: [TabBarItem] = []
    
    static func reduce(value: inout [TabBarItem], nextValue: () -> [TabBarItem]) {
        value.append(contentsOf: nextValue())
    }
}

struct TabBarItemViewModifier: ViewModifier {
    let tabBarItem: TabBarItem
    @Binding var selection: TabBarItem
    
    func body(content: Content) -> some View {
        content
            .opacity(selection == tabBarItem ? 1 : 0)
            .preference(key: TabBarItemsPreferenceKey.self, value: [tabBarItem])
    }
}

extension View {
    func tabBarItem(_ tabBarItem: TabBarItem, selection: Binding<TabBarItem>) -> some View {
        self.modifier(TabBarItemViewModifier(tabBarItem: tabBarItem, selection: selection))
    }
}
