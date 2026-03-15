# BitcoinPrices

An iOS app that displays Bitcoin prices in EUR — the current live price and a 14-day historical view — powered by the [CoinGecko API](https://www.coingecko.com/en/api).

---

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/habibmohammadidev/BitCoinPrices.git
cd BitCoinPrices
```

### 2. Add your CoinGecko API key

The app reads the API key from `Info.plist` at runtime. The key itself is injected at build time via an `.xcconfig` file that is **never committed**.

1. Create `Secrets.xcconfig` in the project root (next to `BitconPrices.xcodeproj`):

   ```
   COINGECKO_API_KEY = your_key_here
   ```

2. In Xcode → project → **Info** → **Configurations**, set both **Debug** and **Release** to use `Secrets.xcconfig`.

3. Confirm `Info.plist` contains the entry (already present in the repo):

   ```xml
   <key>CoinGeckoAPIKey</key>
   <string>$(COINGECKO_API_KEY)</string>
   ```

> The app works without a key (CoinGecko free tier), but will be rate-limited. A demo API key is available for free at [coingecko.com/en/api](https://www.coingecko.com/en/api).

### 3. Build and run

Open `BitconPrices.xcodeproj` in Xcode 16+ and run on any iOS 17+ simulator or device.

---

## Architecture

The app follows a layered architecture where each layer has a single responsibility and dependencies only flow inward.

```
View  →  ViewModel  →  Repository  →  Networking
```

### Networking

| File | Role |
|------|------|
| `HttpDataTransport` | Protocol over `URLSession`. Single method: `data(for:)`. Makes the network layer trivially mockable. |
| `RetryingNetworkClient` | `actor` that wraps any `HttpDataTransport` and adds API-key injection and exponential-backoff retry on transient failures (429, 5xx, `URLError`). |
| `CoinGeckoEndpoint` | Type-safe URL builder. All raw string manipulation lives here, keeping the repository clean. |
| `CoinGeckoResponse` | `Decodable` structs that map the raw JSON. Mapping to domain types is done in `asDomain` extensions, keeping the models free of business logic. |
| `APIKeyProvider` | Reads the API key from `Info.plist`. Isolated here so no other layer knows where the key comes from. |

### Repository

`BitcoinRepository` is a protocol with a single method:

```swift
func prices() -> AsyncStream<PriceUpdate>
```

`LiveBitcoinRepository` is an `actor` that implements it:

- On first subscription it fetches **historical prices** and the **current price in parallel** using `async let`.
- It then enters a **polling loop**, emitting a new `PriceUpdate` every 60 seconds.
- Historical data is **cached per calendar day** — no redundant network calls within the same day.
- Each `PriceUpdate` carries independent `todayError` and `historicalError` fields, so a failure in one source does not suppress data from the other.

### ViewModel

`PriceListViewModel` is a `@MainActor final class` that consumes the `AsyncStream<PriceUpdate>` and maps it to `PriceListViewState`:

- `idle` — before the first load
- `loading` — first fetch in flight
- `loaded([PriceRow])` — success; rows are pre-formatted strings, ready for the view to bind directly
- `error(String)` — both fetches failed and no data has ever loaded

The partial-failure rules are handled here rather than in the view:

- Both fail with no existing data → `.error` state (full-screen error)
- Historical fails, current succeeds → warning banner row prepended to the list
- Current fails, historical succeeds → red error detail on today's row

`PriceRow` is a flat, pre-formatted value type. The view never calls a formatter or touches a `Calendar` — all display decisions are made in the view model.

### View

- `PriceListView` is generic over `PriceListViewModelProtocol`, making it independently previewable and testable with a mock.
- `PriceDetailView` receives a pre-formatted `PriceRow` and renders it — zero business logic.
- SwiftUI Previews cover all four states (both succeed, historical fails, current fails, both fail).

### Testing

| Layer | Approach |
|-------|----------|
| Networking | `MockNetworkClient` and `SequencedMockNetworkClient` inject canned `Data` or errors |
| Repository | `MockBitcoinRepository` emits a controlled `AsyncStream<PriceUpdate>` |
| ViewModel | Unit-tested against `MockBitcoinRepository`; all partial-failure branches are covered |
| UI | `XCUITest` suite covers the happy path and pull-to-refresh |

### Key design decisions

- **`actor` for isolation** — `LiveBitcoinRepository` and `RetryingNetworkClient` are actors. Shared mutable state (cache, retry counter) is protected by the actor's serial executor rather than locks or `DispatchQueue`.
- **`AsyncStream` over Combine** — the repository surface is a plain Swift concurrency primitive. The view model consumes it with `for await`, keeping the reactive plumbing off the public API.
- **Protocol boundaries at every seam** — `HttpDataTransport`, `BitcoinRepository`, and `PriceListViewModelProtocol` are all protocols, so every layer can be substituted in tests without subclassing or method swizzling.
- **Partial failure as first-class data** — `PriceUpdate` carries optional errors alongside data. The view model decides how to present partial failures; the repository never silently swallows them or hard-fails on a single source.
- **No domain types in the view** — `PriceRow` is the boundary. Formatters, calendars, and error localisation all live in the view model.
