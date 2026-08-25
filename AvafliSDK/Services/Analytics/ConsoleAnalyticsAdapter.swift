//
//  ConsoleAnalyticsAdapter.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 2/18/26.
//

import Foundation
import os.log

/// Default analytics adapter that logs events to the system console via `os_log`.
///
/// The SDK uses this automatically when no custom adapter is provided, so
/// publishers see analytics events in Xcode / Console.app without extra setup.
///
/// To replace with your own provider:
/// ```swift
/// let options = AvafliOptions(
///     analyticsAdapter: MyFirebaseAnalyticsAdapter()
/// )
/// ```
public final class ConsoleAnalyticsAdapter: AnalyticsAdapter {

    private let log = OSLog(subsystem: "com.winr.sdk", category: "Analytics")

    public init() {}

    public func track(event: String, properties: [String: Any]?) {
        if let props = properties, !props.isEmpty {
            let pairs = props
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            os_log("[Avafli] %{public}@ | %{public}@", log: log, type: .info, event, pairs)
        } else {
            os_log("[Avafli] %{public}@", log: log, type: .info, event)
        }
    }
}
