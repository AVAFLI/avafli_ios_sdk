//
//  DailyEntryGrant.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation

public struct DailyEntryGrant {
    public let baseEntries: Int
    public let bonusEntries: Int

    public var total: Int { baseEntries + bonusEntries }

    public init(baseEntries: Int, bonusEntries: Int = 0) {
        self.baseEntries = baseEntries
        self.bonusEntries = bonusEntries
    }
}
