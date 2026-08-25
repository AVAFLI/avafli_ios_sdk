//
//  AvafliExperienceViewController.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import SwiftUI
import UIKit

final class AvafliExperienceViewController: UIViewController {

    private let viewModel: AvafliExperienceViewModel
    private let theme: AvafliBranding

    init(viewModel: AvafliExperienceViewModel, theme: AvafliBranding) {
        self.viewModel = viewModel
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        let root = AvafliExperienceView(viewModel: viewModel, theme: theme)
        let hosting = UIHostingController(rootView: root)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)

        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        hosting.didMove(toParent: self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closeRequested),
            name: .avafliCloseRequested,
            object: nil
        )
    }

    @objc private func closeRequested() {
        dismiss(animated: true, completion: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
