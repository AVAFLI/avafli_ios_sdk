//
//  Logger.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation

final class Logger {
    static let shared = Logger()
    var level: AvafliOptions.LoggingLevel = .error

    func log(_ message: String, level: AvafliOptions.LoggingLevel = .info) {
        guard shouldLog(level) else { return }
        print("[AvafliSDK] \(message)")
    }

    private func shouldLog(_ level: AvafliOptions.LoggingLevel) -> Bool {
        switch (self.level, level) {
        case (.none, _): return false
        case (.error, .info), (.error, .debug): return false
        case (.info, .debug): return false
        default: return true
        }
    }
}
