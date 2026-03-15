//
//  BitconPricesTests.swift
//  BitconPricesTests
//

import Testing
import Foundation
@testable import BitconPrices

extension Tag {
    @Tag static var integration: Self
}

// MARK: - Fixture JSON

private let validCurrentPriceJSON = """
{
    "bitcoin": { "eur": 58000.5, "usd": 63000.0, "gbp": 50000.25 }
}
""".data(using: .utf8)!

private let validMarketChartJSON = """
{
    "prices": [
        [1700000000000, 36000.0],
        [1700086400000, 37000.0],
        [1700172800000, 38000.0]
    ]
}
""".data(using: .utf8)!

private let malformedJSON = "not json".data(using: .utf8)!

// MARK: - Helpers

private func makeUpdate(
    historical: Result<[DailyPrice], BitcoinPriceError>,
    current: Result<DailyPrice, BitcoinPriceError>? = nil
) -> PriceUpdate {
    var items: [DailyPrice] = (try? historical.get()) ?? []
    var todayError: BitcoinPriceError?
    var historicalError: BitcoinPriceError?

    if case .failure(let err) = historical {
        historicalError = err
    }

    if let current {
        switch current {
        case .success(let today):
            if let index = items.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: today.date) }) {
                items[index] = today
            } else {
                items.append(today)
            }
        case .failure(let err):
            todayError = err
        }
    }

    return PriceUpdate(items: items, todayError: todayError, historicalError: historicalError)
}

// MARK: - CoinGeckoEndpoint Tests

@Suite("CoinGeckoEndpoint")
struct CoinGeckoEndpointTests {

    @Test("currentPrice builds a valid URL containing expected query params")
    func currentPriceURL() throws {
        let request = try CoinGeckoEndpoint.currentPrice.urlRequest.get()
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)

        #expect(components.path.hasSuffix("/simple/price"))
        #expect(items.contains(URLQueryItem(name: "ids", value: "bitcoin")))
        #expect(items.contains(URLQueryItem(name: "vs_currencies", value: "eur")))
    }

    @Test("historicalPrices builds a valid URL with correct days parameter")
    func historicalPricesURL() throws {
        let request = try CoinGeckoEndpoint.historicalPrices(days: 14).urlRequest.get()
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)

        #expect(components.path.hasSuffix("/coins/bitcoin/market_chart"))
        #expect(items.contains(URLQueryItem(name: "vs_currency", value: "eur")))
        #expect(items.contains(URLQueryItem(name: "days", value: "14")))
        #expect(items.contains(URLQueryItem(name: "interval", value: "daily")))
    }
}

// MARK: - LiveBitcoinRepository Tests

@Suite("LiveBitcoinRepository")
struct LiveBitcoinRepositoryTests {

    @Test("prices stream yields initial history sorted newest-first")
    func prices_initialHistoryEmission() async throws {
        let mock = SequencedMockNetworkClient()
        mock.enqueue(data: validMarketChartJSON, statusCode: 200)  // history
        mock.enqueue(data: validCurrentPriceJSON, statusCode: 200) // current
        let repo = LiveBitcoinRepository(client: mock)

        var first: PriceUpdate?
        for await update in repo.prices() {
            first = update
            break
        }

        let update = try #require(first)
        #expect(update.historicalError == nil)
        // 3 historical entries + today upserted from current price.
        #expect(update.items.count >= 3)
        #expect(update.items[0].date >= update.items[1].date)
        #expect(update.items[1].date >= update.items[2].date)
    }

    @Test("prices stream yields .failure for malformed history JSON but still emits current")
    func prices_historyDecodingError_currentSucceeds() async throws {
        let mock = SequencedMockNetworkClient()
        mock.enqueue(data: malformedJSON, statusCode: 200)         // history fails
        mock.enqueue(data: validCurrentPriceJSON, statusCode: 200) // current succeeds
        let repo = LiveBitcoinRepository(client: mock)

        var first: PriceUpdate?
        for await update in repo.prices() {
            first = update
            break
        }

        let update = try #require(first)
        #expect(update.historicalError == .decodingError)
        #expect(update.todayError == nil)
    }

    @Test("prices stream yields .failure for non-2xx history response")
    func prices_historyHttpError() async throws {
        let mock = SequencedMockNetworkClient()
        mock.enqueue(statusCode: 429)                              // history fails
        mock.enqueue(data: validCurrentPriceJSON, statusCode: 200) // current succeeds
        let repo = LiveBitcoinRepository(client: mock)

        var first: PriceUpdate?
        for await update in repo.prices() {
            first = update
            break
        }

        let update = try #require(first)
        #expect(update.historicalError == .httpError(statusCode: 429))
    }

    @Test("prices stream yields .failure wrapping URLError for history")
    func prices_historyNetworkError() async throws {
        let mock = SequencedMockNetworkClient()
        mock.enqueue(error: URLError(.notConnectedToInternet)) // history fails
        mock.enqueue(data: validCurrentPriceJSON, statusCode: 200)
        let repo = LiveBitcoinRepository(client: mock)

        var first: PriceUpdate?
        for await update in repo.prices() {
            first = update
            break
        }

        let update = try #require(first)
        #expect(update.historicalError == .networkError(URLError(.notConnectedToInternet)))
    }

    @Test("prices stream emits live-poll updates after initial load")
    func prices_livePollUpdates() async throws {
        let mock = SequencedMockNetworkClient()
        mock.enqueue(data: validMarketChartJSON, statusCode: 200)  // initial history
        mock.enqueue(data: validCurrentPriceJSON, statusCode: 200) // initial current
        mock.enqueue(data: validMarketChartJSON, statusCode: 200)  // poll history (cached — won't hit)
        mock.enqueue(data: validCurrentPriceJSON, statusCode: 200) // poll current
        let repo = LiveBitcoinRepository(client: mock, pollInterval: 0.05)

        var collected: [PriceUpdate] = []
        for await update in repo.prices() {
            collected.append(update)
            if collected.count == 2 { break }
        }

        #expect(collected.count == 2)
        for update in collected {
            #expect(update.historicalError == nil)
            #expect(update.items == update.items.sorted { $0.date > $1.date })
        }
    }

    @Test("prices stream yields current failure without terminating the stream")
    func prices_livePollCurrentFailure() async throws {
        let mock = SequencedMockNetworkClient()
        mock.enqueue(data: validMarketChartJSON, statusCode: 200)  // initial history
        mock.enqueue(data: validCurrentPriceJSON, statusCode: 200) // initial current
        mock.enqueue(statusCode: 500)                              // poll current fails
        let repo = LiveBitcoinRepository(client: mock, pollInterval: 0.01)

        var collected: [PriceUpdate] = []
        for await update in repo.prices() {
            collected.append(update)
            if collected.count == 2 { break }
        }

        #expect(collected.count == 2)
        // First: both succeed.
        #expect(collected[0].historicalError == nil)
        #expect(collected[0].todayError == nil)
        // Second: current fails, historical still carried as success (cache).
        #expect(collected[1].historicalError == nil)
        #expect(collected[1].todayError == .httpError(statusCode: 500))
    }
}

// MARK: - RetryingNetworkClient Tests

@Suite("RetryingNetworkClient")
struct RetryingNetworkClientTests {

    // MARK: Interceptor

    @Test("injects the API key header when a key is provided")
    func injectsAPIKeyHeader() async throws {
        let mock = MockNetworkClient()
        mock.stub(data: Data())
        let client = RetryingNetworkClient(
            underlying: mock,
            policy: RetryPolicy(maxAttempts: 0, baseDelay: 0),
            apiKey: "test-key-123"
        )

        _ = try await client.data(for: URLRequest(url: URL(string: "https://example.com")!))

        let sentHeader = mock.capturedRequests.first?.value(forHTTPHeaderField: "x-cg-demo-api-key")
        #expect(sentHeader == "test-key-123")
    }

    @Test("sends request without header when no API key is configured")
    func noHeaderWhenKeyAbsent() async throws {
        let mock = MockNetworkClient()
        mock.stub(data: Data())
        let client = RetryingNetworkClient(
            underlying: mock,
            policy: RetryPolicy(maxAttempts: 0, baseDelay: 0),
            apiKey: nil
        )

        _ = try await client.data(for: URLRequest(url: URL(string: "https://example.com")!))

        let sentHeader = mock.capturedRequests.first?.value(forHTTPHeaderField: "x-cg-demo-api-key")
        #expect(sentHeader == nil)
    }

    // MARK: Retry on HTTP errors

    @Test("retries on 429 and succeeds on subsequent attempt")
    func retries_on429_thenSucceeds() async throws {
        let mock = SequencedMockNetworkClient()
        mock.enqueue(statusCode: 429)
        mock.enqueue(data: Data(), statusCode: 200)

        let client = RetryingNetworkClient(
            underlying: mock,
            policy: RetryPolicy(maxAttempts: 1, baseDelay: 0),
            apiKey: nil
        )

        let (_, response) = try await client.data(for: URLRequest(url: URL(string: "https://example.com")!))
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)
        #expect(mock.callCount == 2)
    }

    @Test("exhausts all retries and returns the final retryable response")
    func exhaustsRetries_returnsLastResponse() async throws {
        let mock = SequencedMockNetworkClient()
        mock.enqueue(statusCode: 503)
        mock.enqueue(statusCode: 503)
        mock.enqueue(statusCode: 503)

        let client = RetryingNetworkClient(
            underlying: mock,
            policy: RetryPolicy(maxAttempts: 2, baseDelay: 0),
            apiKey: nil
        )

        let (_, response) = try await client.data(for: URLRequest(url: URL(string: "https://example.com")!))
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 503)
        #expect(mock.callCount == 3)
    }

    @Test("does not retry on non-retryable status codes")
    func noRetry_on404() async throws {
        let mock = SequencedMockNetworkClient()
        mock.enqueue(statusCode: 404)

        let client = RetryingNetworkClient(
            underlying: mock,
            policy: RetryPolicy(maxAttempts: 3, baseDelay: 0),
            apiKey: nil
        )

        let (_, response) = try await client.data(for: URLRequest(url: URL(string: "https://example.com")!))
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 404)
        #expect(mock.callCount == 1)
    }

    // MARK: Retry on URLError

    @Test("retries on transient URLError and succeeds on subsequent attempt")
    func retries_onTransientURLError() async throws {
        let mock = SequencedMockNetworkClient()
        mock.enqueue(error: URLError(.timedOut))
        mock.enqueue(data: Data(), statusCode: 200)

        let client = RetryingNetworkClient(
            underlying: mock,
            policy: RetryPolicy(maxAttempts: 1, baseDelay: 0),
            apiKey: nil
        )

        let (_, response) = try await client.data(for: URLRequest(url: URL(string: "https://example.com")!))
        let http = try #require(response as? HTTPURLResponse)

        #expect(http.statusCode == 200)
        #expect(mock.callCount == 2)
    }

    @Test("does not retry on non-transient URLError")
    func noRetry_onNonTransientURLError() async throws {
        let mock = SequencedMockNetworkClient()
        mock.enqueue(error: URLError(.badURL))

        let client = RetryingNetworkClient(
            underlying: mock,
            policy: RetryPolicy(maxAttempts: 3, baseDelay: 0),
            apiKey: nil
        )

        await #expect(throws: URLError.self) {
            _ = try await client.data(for: URLRequest(url: URL(string: "https://example.com")!))
        }
        #expect(mock.callCount == 1)
    }
}

// MARK: - Integration Tests (live network)

@Suite("CoinGecko Integration", .tags(.integration))
struct CoinGeckoIntegrationTests {

    @Test("prices stream emits initial load and a live-poll update from CoinGecko")
    func prices_liveNetwork() async throws {
        let repo = LiveBitcoinRepository.live()

        var collected: [PriceUpdate] = []
        for await update in repo.prices() {
            collected.append(update)
            if collected.count == 2 { break }
        }

        let initial = try #require(collected.first)
        #expect(initial.historicalError == nil)
        #expect(initial.items.count >= 13)
        #expect(initial.items.count <= 15)
        #expect(initial.items.allSatisfy { $0.eurPrice > 0 })
    }
}

// MARK: - PriceListViewModel Tests

@Suite("PriceListViewModel")
@MainActor
struct PriceListViewModelTests {

    private func makeVM(updates: [PriceUpdate]) -> PriceListViewModel {
        let repo = MockBitcoinRepository()
        repo.stubbedUpdates = updates
        return PriceListViewModel(repository: repo)
    }

    @Test("load transitions to loaded state when both historical and current succeed")
    func load_bothSucceed() async throws {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let today = DailyPrice(date: now, eurPrice: 58_000)
        let hist  = DailyPrice(date: yesterday, eurPrice: 50_000)
        let vm = makeVM(updates: [makeUpdate(historical: .success([today, hist]),
                                             current: .success(today))])

        await vm.load()
        try await Task.sleep(nanoseconds: 50_000_000)

        guard case .loaded(let rows) = vm.state else {
            Issue.record("Expected .loaded, got \(vm.state)"); return
        }
        #expect(rows.count == 2)
        #expect(rows[0].areLabelsBold)
        #expect(rows[0].dateLabel == "Today")
        #expect(rows[0].detail?.isError == false)
    }

    @Test("load shows full error when both historical and current fail and nothing is loaded")
    func load_bothFail_noExistingRows() async throws {
        let vm = makeVM(updates: [makeUpdate(
            historical: .failure(.networkError(URLError(.notConnectedToInternet))),
            current: .failure(.networkError(URLError(.notConnectedToInternet)))
        )])

        await vm.load()
        try await Task.sleep(nanoseconds: 50_000_000)

        if case .error = vm.state { } else {
            Issue.record("Expected .error state, got \(vm.state)")
        }
    }

    @Test("load shows warning row when historical fails but current succeeds")
    func load_historicalFails_currentSucceeds() async throws {
        let today = DailyPrice(date: Date(), eurPrice: 58_000)
        let vm = makeVM(updates: [makeUpdate(
            historical: .failure(.httpError(statusCode: 503)),
            current: .success(today)
        )])

        await vm.load()
        try await Task.sleep(nanoseconds: 50_000_000)

        guard case .loaded(let rows) = vm.state else {
            Issue.record("Expected .loaded, got \(vm.state)"); return
        }
        // Warning row + today row.
        #expect(rows.count == 2)
        let warningRow = rows.first(where: { $0.priceLabel.isEmpty })
        #expect(warningRow != nil)
        #expect(warningRow?.detail?.isError == true)
        let todayRow = rows.first(where: { $0.areLabelsBold })
        #expect(todayRow != nil)
    }

    @Test("load shows red today detail when historical succeeds but current fails")
    func load_historicalSucceeds_currentFails() async throws {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let vm = makeVM(updates: [makeUpdate(
            historical: .success([
                DailyPrice(date: now,       eurPrice: 55_000),
                DailyPrice(date: yesterday, eurPrice: 50_000)
            ]),
            current: .failure(.httpError(statusCode: 429))
        )])

        await vm.load()
        try await Task.sleep(nanoseconds: 50_000_000)

        guard case .loaded(let rows) = vm.state else {
            Issue.record("Expected .loaded, got \(vm.state)"); return
        }
        #expect(rows.count == 2)
        let todayRow = rows.first(where: { $0.areLabelsBold })
        #expect(todayRow?.detail?.isError == true)
    }

    @Test("subsequent current failure patches today row red without replacing the list")
    func load_subsequentCurrentFailure_patchesTodayDetail() async throws {
        let now = Date()
        let today = DailyPrice(date: now, eurPrice: 55_000)
        let vm = makeVM(updates: [
            makeUpdate(historical: .success([today]), current: .success(today)),
            makeUpdate(historical: .success([today]),
                       current: .failure(.networkError(URLError(.notConnectedToInternet))))
        ])

        await vm.load()
        try await Task.sleep(nanoseconds: 50_000_000)

        guard case .loaded(let rows) = vm.state else {
            Issue.record("Expected .loaded, got \(vm.state)"); return
        }
        let todayRow = rows.first(where: { $0.areLabelsBold })
        #expect(todayRow?.detail?.isError == true)
    }

    @Test("load calls prices() on the repository")
    func load_callsRepository() async throws {
        let repo = MockBitcoinRepository()
        let vm = PriceListViewModel(repository: repo)
        await vm.load()

        #expect(repo.callCount == 1)
    }

    @Test("calling load a second time cancels the previous stream and resubscribes")
    func load_secondCall_resubscribes() async throws {
        let repo = MockBitcoinRepository()
        let today = DailyPrice(date: Date(), eurPrice: 55_000)
        repo.stubbedUpdates = [makeUpdate(historical: .success([today]), current: .success(today))]

        let vm = PriceListViewModel(repository: repo)
        await vm.load()
        await vm.load()

        #expect(repo.callCount == 2)
    }
}

// MARK: - MockBitcoinRepository Tests

@Suite("MockBitcoinRepository")
struct MockBitcoinRepositoryTests {

    @Test("prices stream emits all stubbed updates in order then finishes")
    func prices_stubbedValues() async throws {
        let today     = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let update1 = PriceUpdate(items: [DailyPrice(date: yesterday, eurPrice: 50_000)], todayError: nil, historicalError: nil)
        let update2 = PriceUpdate(items: [DailyPrice(date: today,     eurPrice: 55_000)], todayError: nil, historicalError: nil)

        let repo = MockBitcoinRepository()
        repo.stubbedUpdates = [update1, update2]

        var collected: [PriceUpdate] = []
        for await update in repo.prices() {
            collected.append(update)
        }

        #expect(collected.count == 2)
        #expect(repo.callCount == 1)
    }

    @Test("prices stream emits a stubbed failure for historical")
    func prices_stubbedHistoricalFailure() async throws {
        let repo = MockBitcoinRepository()
        repo.stubbedUpdates = [PriceUpdate(items: [], todayError: nil, historicalError: .unknown)]

        var failure: BitcoinPriceError?
        for await update in repo.prices() {
            failure = update.historicalError
        }

        #expect(failure == .unknown)
    }
}
