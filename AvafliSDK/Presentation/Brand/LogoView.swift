//
//  LogoView.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import SwiftUI

struct AvafliLogoView: View {
    let logo: AvafliLogo
    let size: CGSize

    init(logo: AvafliLogo, size: CGSize) {
        self.logo = logo
        self.size = size
    }

    var body: some View {
        content
            .frame(
                width: size.width,
                height: size.height
            )
    }

    @ViewBuilder
    private var content: some View {
        switch logo {
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFill()

        case .remote(let url):
            if #available(iOS 15.0, *) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Color.clear
                    }
                }
            } else {
                Color.clear
            }

        case .system(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .foregroundColor(.white)

        case .bundled(let name):
            Image(name, bundle: .main)
                .resizable()
                .scaledToFit()
        }
    }
}
