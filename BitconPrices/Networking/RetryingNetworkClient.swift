//
//  RetryingNetworkClient.swift
//  BitconPrices
//

import Foundation

// MARK: - Retry policy

/// Describes when and how many times a failed request should be retried.
struct RetryPolicy: Sendable {
    /// Maximum number of retry attempts (not counting the initial attempt).
    let maxAttempts: Int
    /// Base delay in seconds; actual delay = baseDelay * 2^attempt (exponential back-off).
    let baseDelay: TimeInterval
}

// MARK: - RetryingNetworkClient

/// An `actor` that wraps any `HttpDataTransport` and adds two cross-cutting concerns:
///
/// 1. **Interception** – injects the `x-cg-demo-api-key` header on every request
///    using the key from `APIKeyProvider`. If the key is unavailable the request
///    is sent without it (free-tier / demo usage still works without a key).
///
/// 2. **Retry** – on retryable HTTP status codes (429, 5xx) or transient `URLError`s,
///    the request is retried up to `policy.maxAttempts` times with exponential back-off.
///    Actor isolation ensures the attempt counter is mutation-safe across concurrent callers.
actor RetryingNetworkClient: HttpDataTransport {
    private let underlying: HttpDataTransport
    private let policy: RetryPolicy
    private let apiKey: String?
    // Stored as an instance constant so it is always accessed within actor isolation,
    // avoiding any global-state / @MainActor inference issues.
    private let retryableStatusCodes: Set<Int>

    init(underlying: HttpDataTransport, policy: RetryPolicy, apiKey: String?) {
        self.underlying = underlying
        self.policy = policy
        self.apiKey = apiKey
        self.retryableStatusCodes = [429, 500, 502, 503, 504]
    }

    // MARK: - HttpDataTransport

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let intercepted = intercept(request)
        return try await attempt(intercepted, attemptsLeft: policy.maxAttempts)
    }

    // MARK: - Private helpers

    /// Injects the API key header when a key is available.
    private func intercept(_ request: URLRequest) -> URLRequest {
        guard let key = apiKey else { return request }
        var modified = request
        modified.setValue(key, forHTTPHeaderField: "x-cg-demo-api-key")
        return modified
    }

    /// Recursive retry with exponential back-off.
    /// Each call lives entirely within the actor's isolation domain so `attemptsLeft`
    /// is never accessed from outside — no atomics or locks needed.
    private func attempt(
        _ request: URLRequest,
        attemptsLeft: Int
    ) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await underlying.data(for: request)

            // If the server returns a retryable status and we have attempts left, retry.
            if let http = response as? HTTPURLResponse {
               if retryableStatusCodes.contains(http.statusCode),
                attemptsLeft > 0 {
                    try await backOff(attempt: policy.maxAttempts - attemptsLeft)
                    return try await attempt(request, attemptsLeft: attemptsLeft - 1)
                }
                if !(200...299).contains(http.statusCode) {
                    throw BitcoinPriceError.unknown
                }
            }

            return (data, response)

        } catch let urlError as URLError where isTransient(urlError) && attemptsLeft > 0 {
            try await backOff(attempt: policy.maxAttempts - attemptsLeft)
            return try await attempt(request, attemptsLeft: attemptsLeft - 1)
        }
        // Non-retryable errors propagate immediately.
    }

    /// Sleeps for `baseDelay * 2^attempt` seconds (capped at 30 s).
    private func backOff(attempt: Int) async throws {
        let seconds = min(policy.baseDelay * pow(2.0, Double(attempt)), 30)
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Returns `true` for `URLError` codes that are transient and worth retrying.
    private func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}

// MARK: - Default configuration factory

/// Creates the standard production `RetryingNetworkClient`:
/// URLSession transport, 3 retries with 0.5 s base delay, API key from Info.plist.
///
/// `nonisolated` here prevents the Swift compiler from inferring `@MainActor` on this
/// free function, making it callable from `nonisolated` default-argument contexts.
func makeDefaultNetworkClient() -> RetryingNetworkClient {
    RetryingNetworkClient(
        underlying: URLSession.shared,
        policy: RetryPolicy(maxAttempts: 3, baseDelay: 0.5),
        apiKey: try? APIKeyProvider.coinGeckoAPIKey()
    )
}
