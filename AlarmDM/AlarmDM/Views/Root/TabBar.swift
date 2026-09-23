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
        // The same material as the mini player above it, so on a wide window
        // the two read as one bar at the foot of the page instead of a white
        // strip laid across it.
        .background {
            if widthClass == .regular {
                Rectangle().fill(.regularMaterial).ignoresSafeArea(edges: .bottom)
            } else {
                Color(UIColor.systemBackground).ignoresSafeArea(edges: .bottom)
            }
        }
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
