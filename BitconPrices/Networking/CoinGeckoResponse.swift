//
//  CoinGeckoResponse.swift
//  BitconPrices
//

import Foundation

// MARK: - /simple/price

/// Raw response from the /simple/price endpoint.
struct SimplePriceResponse: Decodable, Sendable {
    struct Rates: Decodable, Sendable {
        let eur: Double
    }
    let bitcoin: Rates
}

// MARK: - /coins/bitcoin/market_chart

/// Raw response from the /coins/{id}/market_chart endpoint.
/// Each element in `prices` is a [timestampMs, price] pair.
struct MarketChartResponse: Decodable, Sendable {
    let prices: [[Double]]
}

// MARK: - Mapping helpers

extension SimplePriceResponse {
    var asDomain: BitcoinPrice {
        BitcoinPrice(eur: bitcoin.eur)
    }
}

extension MarketChartResponse {
    /// Converts raw price pairs into `DailyPrice` values.
    /// CoinGecko returns midnight-UTC timestamps; we normalise each to the
    /// start of its UTC day so the id is stable regardless of response jitter.
    func asDomain(using calendar: Calendar = .utcCalendar) -> [DailyPrice] {
        prices.compactMap { pair in
            guard pair.count == 2 else { return nil }
            let date = Date(timeIntervalSince1970: pair[0] / 1000)
            let dayStart = calendar.startOfDay(for: date)
            return DailyPrice(date: dayStart, eurPrice: pair[1])
        }
    }
}

// MARK: - Calendar helper

private extension Calendar {
    static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }
}
