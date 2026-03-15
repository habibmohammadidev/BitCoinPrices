//
//  PriceListView.swift
//  BitconPrices
//

import SwiftUI


// MARK: - Display model

/// A flat, pre-formatted value type the View binds to directly.
/// Keeping domain types (`DailyPrice`) out of the View layer means
/// the View never needs a formatter or calendar logic.
struct PriceRow: Identifiable, Equatable {
    struct Detail: Equatable {
        let text: String
        let isError: Bool
    }
    let id: Date
    let dateLabel: String      // "Today" or "14 Mar 2026"
    let priceLabel: String     // "€58,231"
    let areLabelsBold: Bool
    let detail: Detail?

    func withDetail(_ detail: Detail?) -> PriceRow {
        PriceRow(id: id, dateLabel: dateLabel, priceLabel: priceLabel,
                 areLabelsBold: areLabelsBold, detail: detail)
    }
}

// MARK: - Protocol

/// Contract for the list screen's view model.
/// Using a protocol lets the View stay testable by accepting a mock implementation.
enum PriceListViewState: Equatable {
    case idle
    case loading
    case loaded([PriceRow])
    case error(String)
    
    var isLoaded: Bool {
        if case .loaded = self {
            return true
        } else {
            return false
        }
    }
}

@MainActor
protocol PriceListViewModelProtocol: ObservableObject {
    var state: PriceListViewState { get }

    func load() async
}

// MARK: - View

struct PriceListView<ViewModel: PriceListViewModelProtocol>: View {
    @StateObject var viewModel: ViewModel

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Bitcoin Prices")
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            loadingView
        case .loaded(let rows):
            listView(rows)
        case .error(let message):
            errorView(message: message)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading prices…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func listView(_ rows: [PriceRow]) -> some View {
        List(rows) { row in
            if row.priceLabel.isEmpty {
                // Warning / banner row — not tappable.
                PriceRowView(row: row)
            } else {
                NavigationLink(destination: PriceDetailView(row: row)) {
                    PriceRowView(row: row)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
// MARK: - Row subview

private struct PriceRowView: View {
    let row: PriceRow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.dateLabel)
                    .font(.subheadline)
                    .fontWeight(row.areLabelsBold ? .semibold : .regular)
                if let detail = row.detail {
                    Text(detail.text)
                        .font(.caption2)
                        .foregroundStyle(detail.isError ? .red : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(row.priceLabel)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(row.areLabelsBold ? .primary : .secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Previews

#if DEBUG
import Combine

@MainActor
private final class PreviewPriceListViewModel: PriceListViewModelProtocol {
    @Published private(set) var state: PriceListViewState
    init(state: PriceListViewState) { self.state = state }
    func load() async {}
}

private extension PriceRow {
    static func make(daysAgo: Int, price: Double) -> PriceRow {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Calendar.current.startOfDay(for: Date()))!
        let isToday = daysAgo == 0
        let dateLabel = isToday ? "Today" : DateFormatter.short.string(from: date)
        let priceLabel = NumberFormatter.currencyFormatter.string(from: NSNumber(value: price)) ?? "—"
        return PriceRow(id: date, dateLabel: dateLabel, priceLabel: priceLabel, areLabelsBold: isToday, detail: nil)
    }
}

private let sampleHistoricalRows: [PriceRow] = (1...7).map {
    .make(daysAgo: $0, price: Double(58_000 + $0 * 300))
}

private let sampleTodayRow = PriceRow.make(daysAgo: 0, price: 61_250)
    .withDetail(.init(text: "updates every 60s", isError: false))

#Preview("Both succeed") {
    PriceListView(viewModel: PreviewPriceListViewModel(
        state: .loaded([sampleTodayRow] + sampleHistoricalRows)
    ))
}

#Preview("Historical failed") {
    let warningRow = PriceRow(
        id: Date.distantFuture,
        dateLabel: "Could not load historical prices",
        priceLabel: "",
        areLabelsBold: false,
        detail: nil
    )
    let todayWithError = sampleTodayRow
    return PriceListView(viewModel: PreviewPriceListViewModel(
        state: .loaded([warningRow, todayWithError])
    ))
}

#Preview("Today failed") {
    let todayFailed = sampleTodayRow
        .withDetail(.init(text: "The network connection was lost.", isError: true))
    return PriceListView(viewModel: PreviewPriceListViewModel(
        state: .loaded([todayFailed] + sampleHistoricalRows)
    ))
}

#Preview("Both failed") {
    PriceListView(viewModel: PreviewPriceListViewModel(
        state: .error("The network connection was lost.")
    ))
}

#endif

