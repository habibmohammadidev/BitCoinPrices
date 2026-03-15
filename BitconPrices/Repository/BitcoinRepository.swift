//
//  BitcoinRepository.swift
//  BitconPrices
//

import Foundation

// MARK: - Protocol

/// A single emission from the prices stream.
/// Historical and current are fetched in parallel; each field is independent —
/// a failure in one does not suppress the other.
struct PriceUpdate: Sendable {
    let currentPriceUpdateInterval: TimeInterval
    let items: [DailyPrice]
    let todayError: BitcoinPriceError?
    let historicalError: BitcoinPriceError?
}

/// Contract for fetching Bitcoin price data.
protocol BitcoinRepository: Sendable {
    /// Streams price updates. The first emission carries the historical batch
    /// (and current price if it resolved first). Subsequent emissions are
    /// live-poll updates carrying only the current price.
    nonisolated func prices() -> AsyncStream<PriceUpdate>
}

// MARK: - Live implementation

actor LiveBitcoinRepository: BitcoinRepository {
    private let client: HttpDataTransport
    private let decoder: JSONDecoder
    private let days: Int
    private let pollInterval: TimeInterval

    /// Cached historical prices for the current calendar day.
    private var cachedPrices: [DailyPrice] = []
    /// The local calendar day on which `cachedPrices` was last populated.
    private var lastFetchedDay: Date?
    /// The running poll/update task. Cancelled and replaced on each call to `prices()`.
    private var updateTask: Task<Void, Never>?

    init(client: HttpDataTransport, days: Int = 14, pollInterval: TimeInterval = 60) {
        self.client = client
        self.decoder = JSONDecoder()
        self.days = days
        self.pollInterval = pollInterval
    }

    static func live() -> LiveBitcoinRepository {
        LiveBitcoinRepository(client: makeDefaultNetworkClient())
    }

    // MARK: - BitcoinRepository

    nonisolated func prices() -> AsyncStream<PriceUpdate> {
        AsyncStream { continuation in
            Task {
                // Cancel any previously running update task before starting a new one.
                await cancelAndReplaceUpdateTask(continuation: continuation)
            }
        }
    }

    private func cancelAndReplaceUpdateTask(
        continuation: AsyncStream<PriceUpdate>.Continuation
    ) {
        updateTask?.cancel()
        updateTask = Task {
            // 1. Initial load: fetch history and current price in parallel.
            async let historicalFetch = fetchHistoricalPrices(days: days)
            async let currentFetch = fetchCurrentPrice()

            let (historicalResult, currentResult) = await (historicalFetch, currentFetch)
            continuation.yield(buildUpdate(historical: historicalResult, current: currentResult))

            // 2. Live polling loop — emit current-price updates only.
            var lastHistorical = historicalResult
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }

                // On day rollover, re-fetch history alongside the live price.
                if shouldFetchHistorical() {
                    lastHistorical = await fetchHistoricalPrices(days: days)
                }
                let liveResult = await fetchCurrentPrice()
                continuation.yield(buildUpdate(historical: lastHistorical, current: liveResult))
            }
            continuation.finish()
        }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.cancelUpdateTask() }
        }
    }

    private func cancelUpdateTask() {
        updateTask?.cancel()
        updateTask = nil
    }

    // MARK: - Private helpers

    private func buildUpdate(
        historical: Result<[DailyPrice], BitcoinPriceError>,
        current: Result<DailyPrice, BitcoinPriceError>
    ) -> PriceUpdate {
        var items: [DailyPrice] = (try? historical.get()) ?? []
        if let today = try? current.get() {
            items.removeAll { Calendar.current.isDateInToday($0.date) }
            items.insert(today, at: 0)
        }
        cachedPrices = items
        let todayError: BitcoinPriceError? = { if case .failure(let e) = current { return e }; return nil }()
        let historicalError: BitcoinPriceError? = { if case .failure(let e) = historical { return e }; return nil }()
        return PriceUpdate(
            currentPriceUpdateInterval: pollInterval,
            items: items,
            todayError: todayError,
            historicalError: historicalError
        )
    }

    private func fetchHistoricalPrices(days: Int) async -> Result<[DailyPrice], BitcoinPriceError> {
        do {
            let prices = try await fetchHistory(days: days)
            return .success(prices)
        } catch {
            return .failure(error)
        }
    }

    private func fetchCurrentPrice() async -> Result<DailyPrice, BitcoinPriceError> {
        do {
            let price = try await fetchLivePrice()
            let today = Calendar.current.startOfDay(for: Date())
            return .success(DailyPrice(date: today, eurPrice: price.eur))
        } catch {
            return .failure(error)
        }
    }

    private func shouldFetchHistorical() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return lastFetchedDay == nil || lastFetchedDay != today
    }

    /// Fetches the full `days`-day history, caches and returns sorted prices.
    /// Returns the cache when the day hasn't changed and data is present.
    private func fetchHistory(days: Int) async throws(BitcoinPriceError) -> [DailyPrice] {
        let today = Calendar.current.startOfDay(for: Date())

        if lastFetchedDay == today, !cachedPrices.isEmpty {
            return cachedPrices
        }

        if lastFetchedDay != today {
            cachedPrices.removeAll(keepingCapacity: true)
        }

        let request = try CoinGeckoEndpoint.historicalPrices(days: days).urlRequest.get()
        let data = try await perform(request)
        let prices: [DailyPrice]
        do {
            let response = try decoder.decode(MarketChartResponse.self, from: data)
            prices = response.asDomain()
        } catch {
            throw .decodingError
        }

        cachedPrices = prices.sorted { $0.date > $1.date }
        lastFetchedDay = today
        // Strip today — current-price is the authoritative source for today.
        return cachedPrices
    }

    private func fetchLivePrice() async throws(BitcoinPriceError) -> BitcoinPrice {
        let request = try CoinGeckoEndpoint.currentPrice.urlRequest.get()
        let data = try await perform(request)
        do {
            let response = try decoder.decode(SimplePriceResponse.self, from: data)
            return response.asDomain
        } catch {
            throw .decodingError
        }
    }

    private func perform(_ request: URLRequest) async throws(BitcoinPriceError) -> Data {
        do {
            let (data, response) = try await client.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw BitcoinPriceError.httpError(statusCode: http.statusCode)
            }
            return data
        } catch let error as BitcoinPriceError {
            throw error
        } catch let error as URLError {
            throw .networkError(error)
        } catch {
            throw .unknown
        }
    }
}
