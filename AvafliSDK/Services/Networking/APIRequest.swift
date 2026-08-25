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
}
