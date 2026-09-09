//
//  ShowViewModel.swift
//  AlarmDM
//
//  Created by Marko Stajic on 22.10.2024.
//

import SwiftUI

class ShowViewModel: ObservableObject {
    @Published var shows: [Show] = [
        .alarmSaDaskomIMladjom,
        .provizorniPodnevniProgram,
        .ljudiIzPodzemlja,
        .vecernjaSkolaRokenrola,
        .unutrasnjaEmigracija,
        .sportskiPozdrav,
        .naIviciOfsajda,
        .rastrojavanje,
        .topleLjuckePrice
    ]
}
