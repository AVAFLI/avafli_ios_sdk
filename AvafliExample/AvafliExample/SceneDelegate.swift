//
//  SceneDelegate.swift
//  AvafliExample
//
//  Standard scene lifecycle — sets ContentView as the root.
//

import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {

        guard let windowScene = (scene as? UIWindowScene) else { return }

        // Switch to SwiftUI for cooler animations & effects
        let contentView = ContentView()
        let hostingController = UIHostingController(rootView: contentView)
        
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = hostingController
        window.makeKeyAndVisible()

        self.window = window
    }
}
