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
    public static let sdkVersion = "3.1.4"
    public static let platformOS = "iOS"

    // Hardcoded privacy policy URL — consistent across all publishers.
    // (Official Rules URLs are server-fed per giveaway/config, never hardcoded.)
    static let privacyURL = "https://sdk.avafli.com/sdk/privacy"
}

/// When the SDK is allowed to open the experience on its own (the once-a-day
/// auto-open). Registration and analytics run on `Avafli.configure(_:)` in
/// every mode — the mode only decides whether the drawer appears by itself.
public enum AvafliAutoOpen {
    /// The default: auto-open once per calendar day whenever the user is
    /// eligible (exactly the behavior of every earlier release).
    case always
    /// Skip the auto-open for the session in which this device registered
    /// for the very first time (the backend reported a brand-new user), so a
    /// first-run onboarding is never covered by the drawer. Every later
    /// launch auto-opens as normal. Present the drawer yourself that first
    /// time with `Avafli.present()` once onboarding is done.
    case returningUsersOnly
    /// The SDK never opens the experience on its own; the host presents it
    /// with `Avafli.present()` (a button, a screen, the end of onboarding).
    case never
}

extension AvafliAutoOpen {
    /// Parses the server-side `experience.autoOpenMode`. Unknown or absent
    /// values are ignored (→ `.always`) so a newer backend can never lock an
    /// older SDK out by accident.
    init(serverValue: String?) {
        switch serverValue {
        case "returningUsersOnly": self = .returningUsersOnly
        case "never": self = .never
        default: self = .always
        }
    }

    /// Ordering for "most restrictive wins": never > returningUsersOnly > always.
    private var restrictiveness: Int {
        switch self {
        case .always: return 0
        case .returningUsersOnly: return 1
        case .never: return 2
        }
    }

    /// Effective mode = the most restrictive of the server kill switch
    /// (`experience.autoOpenEnabled === false` → never), the server mode and
    /// the client mode.
    static func effective(client: AvafliAutoOpen, serverEnabled: Bool?, serverMode: AvafliAutoOpen) -> AvafliAutoOpen {
        if serverEnabled == false { return .never }
        return client.restrictiveness >= serverMode.restrictiveness ? client : serverMode
    }
}

public struct AvafliConfiguration {
    public let apiKey: String
    public let environment: AvafliEnvironment
    public let bundleId: String
    public let user: AvafliUser
    public let options: AvafliOptions
    /// When the SDK may open the experience on its own. Default `.always`
    /// (unchanged behavior). See `AvafliAutoOpen`.
    public let autoOpen: AvafliAutoOpen

    public init(
        apiKey: String,
        environment: AvafliEnvironment = .production,
        bundleId: String,
        user: AvafliUser,
        options: AvafliOptions = .init(),
        autoOpen: AvafliAutoOpen = .always
    ) {
        self.apiKey = apiKey
        self.environment = environment
        self.bundleId = bundleId
        self.user = user
        self.options = options
        self.autoOpen = autoOpen
    }
}
