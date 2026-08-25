//
//  AvafliUser.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation

public struct AvafliUser {
    /// Your app's unique user ID (Firebase UID, database ID, etc.)
    public let id: String

    /// User's first name (optional — the SDK collects it at prize-claim if missing)
    public let firstName: String

    /// User's last name (optional — the SDK collects it at prize-claim if missing)
    public let lastName: String

    /// User's phone number (optional, for SMS notifications)
    public var phone: String?

    /// The user's email from YOUR authenticated session (optional).
    ///
    /// When supplied, the Avafli capture screen shows it pre-filled and
    /// READ-ONLY — the user cannot swap in a different address. That is
    /// deliberate: Avafli links accounts across devices by email, so a
    /// free-typed address lets a user attach themselves to someone else's
    /// record, and a partner-authenticated address is the most reliable
    /// destination for a winner notification.
    ///
    /// Supplying it never records any consent. The user still sees the
    /// address, ticks the age (and optionally marketing) boxes, and submits —
    /// consent remains an explicit act inside the Avafli flow. A malformed
    /// value is ignored and the field stays editable, exactly as if no email
    /// had been passed.
    public var email: String?

    /// Create an Avafli user. Only `id` is required; everything else is optional and
    /// the SDK captures what's missing (email via its capture screen, name via the
    /// winner prize-claim form).
    public init(id: String, firstName: String = "", lastName: String = "", phone: String? = nil, email: String? = nil) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.email = email
    }

    /// A guest session — the person is not signed in to YOUR app (or your app
    /// has no accounts). The SDK mints a stable per-install guest id
    /// (`avafli_guest_…`) and uses it for attribution, so there is always a real
    /// identifier without your integration having to fabricate one. The Avafli
    /// experience is fully functional for guests: it captures its own email and
    /// the streak survives your user later signing in — just call `configure`
    /// again with the real user and attribution upgrades in place.
    public static let guest = AvafliUser(id: "", firstName: "", lastName: "")

    /// True when this value is the `.guest` sentinel.
    var isGuest: Bool { id.isEmpty }
}
