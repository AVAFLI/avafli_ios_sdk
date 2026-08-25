//
//  AvafliExperienceView.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import SwiftUI

struct AvafliExperienceView: View {
    @ObservedObject var viewModel: AvafliExperienceViewModel
    let theme: AvafliBranding

    // V2 (Joe's Avafli-High-V2 designs) is the shipping experience.
    var body: some View {
        AvafliV2ExperienceRoot(viewModel: viewModel)
    }
}

extension Notification.Name {
    static let avafliCloseRequested = Notification.Name("avafliCloseRequested")
}
