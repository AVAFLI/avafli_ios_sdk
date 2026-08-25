//
//  Storage.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation

protocol Storage {
    func save<T: Codable>(_ value: T, for key: String) throws
    func load<T: Codable>(_ type: T.Type, for key: String) throws -> T?
    func remove(for key: String) throws
}

final class UserDefaultsStorage: Storage {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save<T>(_ value: T, for key: String) throws where T : Decodable, T : Encodable {
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: key)
    }

    func load<T>(_ type: T.Type, for key: String) throws -> T? where T : Decodable, T : Encodable {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func remove(for key: String) throws {
        defaults.removeObject(forKey: key)
    }
}
