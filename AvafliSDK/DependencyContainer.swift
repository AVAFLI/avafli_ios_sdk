//
//  DependencyContainer.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

// MARK: - DependencyContainer.swift

import Foundation
import UIKit

struct DependencyContainer {
    let configuration: AvafliConfiguration
    let user: AvafliUser
    let network: NetworkClient
    let storage: Storage
    let keychain: KeychainStorage
    let analytics: AnalyticsAdapter?

    /// Cached giveaway config from registration
    var cachedGiveaway: GiveawayConfig?
    var cachedClaimedToday: Bool?
    var cachedStreakDay: Int?

    /// Server-driven SDK config (copy, branding, rules) set by admin/publisher dashboard
    var sdkConfig: SDKConfigResponse?

    /// Abandoned verification-gated adoption (from the register /
    /// getActiveGiveaway response) — the experience re-stages it on open.
    var adoptionPending: Bool?

    init(configuration: AvafliConfiguration, user: AvafliUser) {
        self.configuration = configuration
        self.user = user

        let baseURL: URL = {
            switch configuration.environment {
            case .production:
                return URL(string: "https://us-central1-winr-9c11f.cloudfunctions.net")!
            }
        }()

        let keychain = KeychainStorage()
        self.keychain = keychain
        self.network = URLSessionNetworkClient(
            baseURL: baseURL,
            apiKey: configuration.apiKey,
            tokenProvider: { keychain.loadToken() },
            refreshHandler: {
                // Use a plain client to avoid recursion
                let plainNetwork = URLSessionNetworkClient(baseURL: baseURL, apiKey: configuration.apiKey, enablePinning: false)
                guard let rt = keychain.loadRefreshToken() else { return nil }
                do {
                    let response = try await plainNetwork.send(RefreshTokenRequest(refreshToken: rt))
                    keychain.saveToken(response.token)
                    keychain.saveRefreshToken(response.refreshToken)
                    return response.token
                } catch {
                    return nil
                }
            },
            enablePinning: false,  // Disabled until pin rotation is automated
        )
        self.storage = UserDefaultsStorage()
        // Route publisher analytics through the offline buffering wrapper so
        // events emitted while offline are queued (bounded, persisted) and
        // flushed on reconnect with their original timestamps.
        self.analytics = AvafliOfflineResilience.shared?
            .analyticsAdapter(wrapping: configuration.options.analyticsAdapter)
            ?? configuration.options.analyticsAdapter
        self.cachedGiveaway = nil
    }
}
