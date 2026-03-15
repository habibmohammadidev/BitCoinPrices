//
//  PriceListViewModel.swift
//  BitconPrices
//

import Foundation
import Combine

@MainActor
final class PriceListViewModel: PriceListViewModelProtocol {

    // MARK: Published

    @Published private(set) var state: PriceListViewState = .idle

    // MARK: Private

    private let repository: BitcoinRepository

    // MARK: Init

    init(repository: BitcoinRepository) {
        self.repository = repository
    }

    // MARK: PriceListViewModelProtocol

    func load() async {
        if !state.isLoaded {
            state = .loading
        }

        for await update in repository.prices() {
            apply(update)
        }
    }

    // MARK: - Private

    /// Applies a `PriceUpdate` to the current state according to the rules:
    /// - Both fail            → full error screen (only if no rows are loaded yet)
    /// - History fails        → warning row prepended to whatever rows exist
    /// - Current fails        → red detail on today's row
    /// - Both succeed         → normal loaded list
    private func apply(_ update: PriceUpdate) {
        // Both fail → full error screen (only if no rows are loaded yet)
        if let historicalError = update.historicalError, update.todayError != nil {
            if !state.isLoaded {
                state = .error(historicalError.localizedDescription)
            }
            return
        }

        // Build base rows from historical data (or keep existing rows on failure).
        var rows: [PriceRow]
        if update.historicalError == nil {
            rows = update.items.map { makeRow($0) }
        } else if case .loaded(let existing) = state {
            rows = existing
        } else {
            rows = []
        }

        // History fails → prepend a warning banner row
        if let historicalError = update.historicalError {
            let warningRow = PriceRow(
                id: Date.distantFuture,
                dateLabel: historicalError.localizedDescription,
                priceLabel: "",
                areLabelsBold: false,
                detail: nil
            )
            rows.insert(warningRow, at: 0)
        }

        // Current fails → attach red detail to today's row
        
        let errorDetail = PriceRow.Detail(
            text: update.todayError?.localizedDescription ?? "updates every \(update.currentPriceUpdateInterval)s",
            isError: update.todayError != nil)
        rows = rows.map { row in
            guard Calendar.current.isDateInToday(row.id) else { return row }
            return row.withDetail(errorDetail)
        }

        state = .loaded(rows)
    }

    private func makeRow(_ daily: DailyPrice, liveDetail: PriceRow.Detail? = nil) -> PriceRow {
        let isToday = Calendar.current.isDateInToday(daily.date)
        let dateLabel = isToday
            ? "Today"
            : DateFormatter.short.string(from: daily.date)
        let priceLabel = NumberFormatter.currencyFormatter
            .string(from: NSNumber(value: daily.eurPrice)) ?? "—"
        let detail: PriceRow.Detail? = isToday ? liveDetail : nil
        return PriceRow(
            id: daily.id,
            dateLabel: dateLabel,
            priceLabel: priceLabel,
            areLabelsBold: isToday,
            detail: detail
        )
    }
}
