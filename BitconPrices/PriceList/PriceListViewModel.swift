//
//  PriceListViewModel.swift
//  BitconPrices
//

import Foundation
import Combine


// MARK: - Implementation

@MainActor
final class PriceListViewModel: PriceListViewModelProtocol {

    // MARK: Published

    @Published private(set) var state: PriceListViewState = .idle

    // MARK: Private

    private let repository: BitcoinRepository
    private var livePriceTask: Task<Void, Never>?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.maximumFractionDigits = 0
        return f
    }()

    // MARK: Init

    init(repository: BitcoinRepository) {
        self.repository = repository
    }

    // MARK: PriceListViewModelProtocol

    func load() async {
        state = .loading
        do {
            let prices = try await repository.fetchDailyPrices(days: 14)
            state = .loaded(prices.sorted { $0.date > $1.date }.map(makeRow))
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func onAppear() {
        livePriceTask?.cancel()
        livePriceTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await price in repository.livePrice(interval: 60) {
                    guard !Task.isCancelled else { break }
                    // Delegate storage mutation to the actor, then re-render.
                    let updated = await repository.updateTodayPrice(price.eur)
                    state = .loaded(updated.sorted { $0.date > $1.date }.map(makeRow))
                }
            } catch {
                // Silently swallow live-update errors; the snapshot stays visible.
            }
        }
    }

    func onDisappear() {
        livePriceTask?.cancel()
        livePriceTask = nil
    }

    // MARK: Private helpers

    private func makeRow(_ daily: DailyPrice) -> PriceRow {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(daily.date)
        let dateLabel = isToday
            ? "Today"
            : Self.dateFormatter.string(from: daily.date)
        let priceLabel = Self.currencyFormatter
            .string(from: NSNumber(value: daily.eurPrice)) ?? "—"
        return PriceRow(id: daily.id, dateLabel: dateLabel, priceLabel: priceLabel, isToday: isToday)
    }
}
