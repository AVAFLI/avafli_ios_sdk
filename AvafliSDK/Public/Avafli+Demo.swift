//
//  Avafli+Demo.swift
//  AvafliSDK
//
//  DEMO-ONLY hooks for the Avafli example app (team demos). Every entry point
//  hard-gates on the example bundle id and no-ops everywhere else, and the
//  backend demoControl callable enforces the same gate server-side.
//  Intentionally undocumented — not part of the public API surface.
//

import Foundation

public extension Avafli {

    private static var isDemoHost: Bool {
        configuration?.bundleId == "com.avafli.winr.example"
    }

    /// Server-side demo action: "resetClaim" | "makeWinner" | "clearWinner".
    /// Completion on the main thread with success.
    static func demoPerform(_ action: String, completion: @escaping (Bool) -> Void) {
        guard isDemoHost, let configuration else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        let container = DependencyContainer(configuration: configuration, user: configuration.user)
        // Re-arm the auto-open up front so a quick app relaunch can't race the
        // network round-trip and miss the reset.
        demoClearDailyMarks()
        Task {
            do {
                _ = try await container.network.send(DemoControlRequest(action: action))
                await MainActor.run { completion(true) }
            } catch {
                Logger.shared.log("[demo] \(action) failed: \(error)", level: .error)
                await MainActor.run { completion(false) }
            }
        }
    }

    /// Full local wipe: keychain identity + every per-user default. The next
    /// launch registers a brand-new user (fresh email capture flow).
    ///
    /// registerDevice looks users up by deviceFingerprint (identifierForVendor,
    /// which is stable across relaunches), so wiping local state alone would
    /// resurrect the SAME backend user. To make the next launch a truly new
    /// user, we also store a fresh random fingerprint override that
    /// `Avafli.deviceIdentifier()` prefers over identifierForVendor (demo host
    /// only).
    static func demoWipeIdentity() {
        guard isDemoHost else { return }
        KeychainStorage().deleteAll()
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("winr") {
            defaults.removeObject(forKey: key)
        }
        demoClearDailyMarks()
        // AFTER the winr-prefixed wipe (the key is winr-prefixed too): fresh
        // fingerprint so the next registerDevice creates a brand-new user.
        if let key = demoFingerprintKey {
            defaults.set(UUID().uuidString, forKey: key)
        }
    }

    /// Clears just the once-per-day auto-open mark + unregistered counter.
    static func demoClearDailyMarks() {
        guard isDemoHost else { return }
        let bundleId = configuration?.bundleId ?? ""
        UserDefaults.standard.removeObject(forKey: "winr_last_auto_present_\(bundleId)")
        UserDefaults.standard.removeObject(forKey: "winr_unregistered_impressions_\(bundleId)")
    }
}

extension Avafli {
    /// UserDefaults key for the demo-only device-fingerprint override.
    /// Non-nil only for the example app bundle — everywhere else the override
    /// machinery is inert and registration uses identifierForVendor.
    internal static var demoFingerprintKey: String? {
        guard let bundleId = configuration?.bundleId,
              bundleId == "com.avafli.winr.example" else { return nil }
        return "winr_demo_fingerprint_\(bundleId)"
    }
}

struct DemoControlRequest: APIRequest {
    typealias Response = DemoControlResponse
    let action: String
    var path: String { "demoControl" }
    var method: String { "POST" }
    var body: Data? {
        try? JSONEncoder().encode(["data": ["action": action]])
    }
}

struct DemoControlResponse: Decodable {
    let ok: Bool?
}
