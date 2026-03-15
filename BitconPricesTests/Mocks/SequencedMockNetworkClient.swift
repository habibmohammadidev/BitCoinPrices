//
//  SequencedMockNetworkClient.swift
//  BitconPricesTests
//

import Foundation
@testable import BitconPrices

/// An `HttpDataTransport` that returns pre-queued responses one per call.
/// Designed for testing retry logic where different attempts need different outcomes.
final class SequencedMockNetworkClient: HttpDataTransport, @unchecked Sendable {
    private var queue: [Result<(Data, URLResponse), Error>] = []
    private(set) var callCount = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1
        guard !queue.isEmpty else {
            throw URLError(.unknown)
        }
        return try queue.removeFirst().get()
    }

    // MARK: - Enqueue helpers

    func enqueue(data: Data = Data(), statusCode: Int) {
        queue.append(.success((data, makeHTTPResponse(statusCode: statusCode))))
    }

    func enqueue(error: URLError) {
        queue.append(.failure(error))
    }
}

// MARK: - Private

private func makeHTTPResponse(statusCode: Int) -> URLResponse {
    HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}
