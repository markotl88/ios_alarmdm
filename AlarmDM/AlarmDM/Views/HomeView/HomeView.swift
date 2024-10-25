//
//  HomeView.swift
//  AlarmDM
//
//  Created by Marko Stajic on 24.10.2024.
//

import Foundation
import SwiftUI

struct HomeView: View {
    
    @StateObject private var viewModel = HomeViewModel() // Initializing the HomeViewModel
    @State private var showPicker: Bool = true // To control Picker visibility
    
    var body: some View {
        VStack {
            if showPicker {
                // Segmented Control
                Picker("", selection: $viewModel.selectedSegment) {
                    Text("Uživo").tag(0)
                    Text("Podkast").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .background(Color("background")) // Applied custom background color
            }
            NavigationView {
                VStack {
                    
                    // Conditionally show RadioView or ShowView based on selected segment
                    if viewModel.selectedSegment == 0 {
                        RadioView() // Your existing RadioView
                    } else {
                        ShowView() // Pass binding to control Picker visibility
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .background(Color("background").edgesIgnoringSafeArea(.all)) // Applied background color
            }
        }
        .accentColor(Color("accent")) // Applied custom accent color to navigation elements
    }
}
// Preview for HomeView
struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
