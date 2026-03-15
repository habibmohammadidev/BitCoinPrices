//
//  BitcoinPrice.swift
//  BitconPrices
//

import Foundation

/// The price of Bitcoin in all three supported fiat currencies for a single point in time.
struct BitcoinPrice: Equatable {
    let eur: Double
}

/// The price entry for a single calendar day.
struct DailyPrice: Equatable {
    let date: Date
    let eurPrice: Double

    var id: Date { date }
}

/// All errors that can be produced by the network / repository layers.
enum BitcoinPriceError: Error, Equatable {
    case invalidURL
    case networkError(URLError)
    case httpError(statusCode: Int)
    case decodingError
    case unknown

    static func == (lhs: BitcoinPriceError, rhs: BitcoinPriceError) -> Bool {
        return switch (lhs, rhs) {
        case (.invalidURL, .invalidURL): true
        case (.networkError(let a), .networkError(let b)): a.code == b.code
        case (.httpError(let a), .httpError(let b)): a == b
        case (.decodingError, .decodingError): true
        case (.unknown, .unknown): true
        default: false
        }
    }
}
