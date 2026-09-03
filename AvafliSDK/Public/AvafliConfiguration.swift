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
    public static let sdkVersion = "3.1.2"
    public static let platformOS = "iOS"

    // Hardcoded privacy policy URL — consistent across all publishers.
    // (Official Rules URLs are server-fed per giveaway/config, never hardcoded.)
    static let privacyURL = "https://sdk.avafli.com/sdk/privacy"
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
