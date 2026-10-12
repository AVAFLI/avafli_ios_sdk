//
//  APIRequest.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation

protocol APIRequest {
    associatedtype Response: Decodable
    var path: String { get }
    var method: String { get } // "GET", "POST"
    var body: Data? { get }
    /// Whether a callable rejection should reach the caller as an
    /// `AvafliCallableFailure` (status, message and the machine-readable
    /// `details`) instead of the message-only `AvafliError`. Off by default —
    /// only the prize-claim calls opt in, so every other caller sees exactly
    /// the errors it always has.
    var surfacesCallableErrorDetails: Bool { get }
}

extension APIRequest {
    var surfacesCallableErrorDetails: Bool { false }
}
