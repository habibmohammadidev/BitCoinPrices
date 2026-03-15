//
//  HttpDataTransport.swift
//  BitconPrices
//

import Foundation

/// A single responsibility abstraction over URLSession.
/// Keeping this as a protocol makes it trivially mockable in tests.
protocol HttpDataTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

// MARK: - Live implementation

extension URLSession: HttpDataTransport {}
