//
//  MockNetworkClient.swift
//  BitconPricesTests
//

import Foundation
@testable import BitconPrices

/// A controllable `HttpDataTransport` for unit tests.
/// Set `stubbedResult` before calling code under test.
final class MockNetworkClient: HttpDataTransport, @unchecked Sendable {
    var stubbedResult: Result<(Data, URLResponse), Error> = .success((Data(), makeHTTPResponse()))

    private(set) var capturedRequests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequests.append(request)
        return try stubbedResult.get()
    }
}

// MARK: - Helpers

private func makeHTTPResponse(statusCode: Int = 200) -> URLResponse {
    HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

extension MockNetworkClient {
    /// Convenience: stub with a 200 OK carrying `data`.
    func stub(data: Data, statusCode: Int = 200) {
        stubbedResult = .success((data, makeHTTPResponse(statusCode: statusCode)))
    }

    /// Convenience: stub with an HTTP error status.
    func stub(statusCode: Int) {
        stubbedResult = .success((Data(), makeHTTPResponse(statusCode: statusCode)))
    }

    /// Convenience: stub with a network-level error.
    func stub(error: URLError) {
        stubbedResult = .failure(error)
    }
}
