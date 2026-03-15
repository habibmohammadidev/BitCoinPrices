//
//  MockBitcoinRepository.swift
//  BitconPricesTests
//

import Foundation
@testable import BitconPrices

/// A fully controllable `BitcoinRepository` for use in ViewModel / integration tests.
final class MockBitcoinRepository: BitcoinRepository, @unchecked Sendable {

    // MARK: - Stubbable results

    /// Emitted in order by `prices()`. Stream finishes after the last value.
    var stubbedUpdates: [PriceUpdate] = []

    // MARK: - Call tracking

    nonisolated(unsafe) private(set) var callCount = 0

    // MARK: - BitcoinRepository

    nonisolated func prices() -> AsyncStream<PriceUpdate> {
        callCount += 1
        let values = stubbedUpdates
        return AsyncStream { continuation in
            Task.detached {
                for update in values {
                    continuation.yield(update)
                }
                continuation.finish()
            }
        }
    }
}
