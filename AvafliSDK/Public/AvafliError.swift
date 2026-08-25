//
//  AvafliError.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation

public enum AvafliError: Error {
    case notConfigured
    case noPresentingViewController
    case network(Error)
    case invalidState
    case ineligibleToday
    case alreadyClaimed
    case invalidAPIKey
    case unauthorizedBundleId
    case giveawayNotActive
    case authenticationRequired
    /// The publisher's Avafli account is suspended or its API key has been
    /// revoked (e.g. billing lapsed). The experience should silently degrade:
    /// default-UI integrations present nothing, custom-UI integrations can
    /// surface their own "unavailable" messaging.
    case serviceUnavailable
    /// The user has exercised their right to delete (RTD) and opted out of Avafli.
    /// The experience must never be presented to them again.
    case optedOut
    /// The backend geo-fence rejected the request (non-US or unverifiable
    /// location). The V2 experience renders a dedicated "Not available in
    /// your location" state for this case.
    case geoBlocked
    case internalError(String)
}

extension AvafliError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Avafli SDK is not configured. Call Avafli.configure(_:) first."
        case .noPresentingViewController:
            return "No presenting view controller could be found."
        case .network(let error):
            return error.localizedDescription
        case .invalidState:
            return "The Avafli experience is in an invalid state."
        case .ineligibleToday:
            return "You are not eligible to claim entries today."
        case .alreadyClaimed:
            return "You have already claimed your entries today."
        case .invalidAPIKey:
            return "The Avafli API key is invalid."
        case .unauthorizedBundleId:
            return "This app's bundle identifier is not authorized for the provided Avafli API key."
        case .giveawayNotActive:
            return "There is no active giveaway right now."
        case .authenticationRequired:
            return "Authentication is required."
        case .serviceUnavailable:
            return "This experience is currently unavailable."
        case .optedOut:
            return "This user has opted out of Avafli."
        case .geoBlocked:
            return "This promotion is not available in the user's location."
        case .internalError(let message):
            return message
        }
    }
}
