//
//  AvafliConfiguration.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation
import SwiftUI

public enum AvafliConstants {
    /// Single source of truth for the SDK version. MUST match `AvafliSDK.podspec`
    /// (`s.version`) and the latest CHANGELOG entry. Format: `v<major>.<minor>.<patch>`.
    public static let sdkVersion = "3.0.1"
    public static let platformOS = "iOS"
    
    // Hardcoded legal URLs — consistent across all publishers
    static let rulesURL = "https://winrmedia.com/sdk/rules"
    static let privacyURL = "https://winrmedia.com/sdk/privacy"
}

public struct AvafliConfiguration {
    public let apiKey: String
    public let environment: AvafliEnvironment
    public let bundleId: String
    public let user: AvafliUser
    public let options: AvafliOptions

    public init(
        apiKey: String,
        environment: AvafliEnvironment = .production,
        bundleId: String,
        user: AvafliUser,
        options: AvafliOptions = .init()
    ) {
        self.apiKey = apiKey
        self.environment = environment
        self.bundleId = bundleId
        self.user = user
        self.options = options
    }
}
