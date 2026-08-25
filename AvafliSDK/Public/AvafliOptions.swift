//
//  AvafliOptions.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation
import SwiftUI

public struct AvafliOptions {
    public enum LoggingLevel { case none, error, info, debug }

    public let logging: LoggingLevel
    public let analyticsAdapter: AnalyticsAdapter?
    public let enablePushReminders: Bool

    public init(
        logging: LoggingLevel = .error,
        analyticsAdapter: AnalyticsAdapter? = ConsoleAnalyticsAdapter(),
        enablePushReminders: Bool = true
    ) {
        self.logging = logging
        self.analyticsAdapter = analyticsAdapter
        self.enablePushReminders = enablePushReminders
    }
}
