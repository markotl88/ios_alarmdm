//
//  ShowView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 22.10.2024.
//

import SwiftUI

struct ShowView: View {
    @StateObject private var viewModel = ShowViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.shows, id: \.self) { show in
                NavigationLink(destination: ContentView(viewModel: ContentViewModel(show: show))) {
                    VStack(alignment: .leading) {
                        Text(show.displayName)
                            .font(.headline)
                        Text(show.description)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Shows")
        }
    }
}

#Preview {
    ShowView()
}
