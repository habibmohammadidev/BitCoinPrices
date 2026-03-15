//
//  CoinGeckoEndpoint.swift
//  BitconPrices
//

import Foundation

/// Type-safe description of every CoinGecko endpoint used by this app.
/// Building URLs here keeps the repository free of raw string manipulation.
enum CoinGeckoEndpoint {
    /// Current price of Bitcoin in EUR, USD and GBP.
    case currentPrice
    /// Daily closing prices for Bitcoin in EUR over the last `days` days.
    case historicalPrices(days: Int)

    // MARK: - URL construction

    private nonisolated static let baseURL = "https://api.coingecko.com/api/v3"

    nonisolated var urlRequest: Result<URLRequest, BitcoinPriceError> {
        var components = URLComponents(string: Self.baseURL)

        switch self {
        case .currentPrice:
            components?.path += "/simple/price"
            components?.queryItems = [
                URLQueryItem(name: "ids", value: "bitcoin"),
                URLQueryItem(name: "vs_currencies", value: "eur")
            ]

        case .historicalPrices(let days):
            components?.path += "/coins/bitcoin/market_chart"
            components?.queryItems = [
                URLQueryItem(name: "vs_currency", value: "eur"),
                URLQueryItem(name: "days", value: "\(days)"),
                URLQueryItem(name: "interval", value: "daily")
            ]
        }

        guard let url = components?.url else {
            return .failure(.invalidURL)
        }
        return .success(URLRequest(url: url))
    }
}
