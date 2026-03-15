//
//  APIKeyProvider.swift
//  BitconPrices
//
// HOW TO SET YOUR API KEY
// ───────────────────────
// 1. Create a file named `Secrets.xcconfig` in the project root (same level as the .xcodeproj).
//    Add it to .gitignore so it is never committed.
//
// 2. Add one line to Secrets.xcconfig:
//       COINGECKO_API_KEY = your_key_here
//
// 3. In Xcode → Project → Info → Configurations, set both Debug and Release
//    to use Secrets.xcconfig (or the xcconfig that includes it).
//
// 4. In the app target's Info.plist, add a new row:
//       Key:   CoinGeckoAPIKey
//       Value: $(COINGECKO_API_KEY)
//
//    Xcode will substitute the build-setting value at build time.
//    The key is only present in the compiled binary – never in source control.

import Foundation

/// Reads the CoinGecko API key that was injected at build time via `Info.plist`.
///
/// Using `Info.plist` + an `.xcconfig` file is the standard iOS approach:
/// - The raw key lives only in a gitignored config file on the developer's machine.
/// - CI/CD injects it as an environment variable (xcodebuild … COINGECKO_API_KEY=$SECRET).
/// - No third-party secrets manager is required.
struct APIKeyProvider {
    enum APIKeyError: Error {
        /// The `CoinGeckoAPIKey` entry is missing from Info.plist or is an empty string.
        case missingAPIKey
    }

    /// Returns the CoinGecko API key, or throws if it has not been configured.
    nonisolated static func coinGeckoAPIKey() throws(APIKeyError) -> String {
        guard
            let key = Bundle.main.object(forInfoDictionaryKey: "CoinGeckoAPIKey") as? String,
            !key.isEmpty
        else {
            throw .missingAPIKey
        }
        return key
    }
}
