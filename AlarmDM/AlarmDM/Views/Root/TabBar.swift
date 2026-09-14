//
//  TabBar.swift
//  AlarmDM
//
//

import SwiftUI

struct TabBar: View {
    @Binding var currentItem: TabBarItem
    @Environment(\.horizontalSizeClass) private var widthClass

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
        // Four labels spread across a window a metre wide are a row of
        // distant, unrelated things. Held together in the middle they stay a
        // tab bar, which is what a thumb and an eye both expect.
        .frame(maxWidth: widthClass == .regular ? 560 : .infinity)
        .frame(maxWidth: .infinity)
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
