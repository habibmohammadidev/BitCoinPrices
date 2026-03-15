//
//  PriceDetailView.swift
//  BitconPrices
//

import SwiftUI

private let detailDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .long
    f.timeStyle = .none
    return f
}()

struct PriceDetailView: View {
    let row: PriceRow

    var body: some View {
        List {
            Section {
                HStack {
                    Text("EUR")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(row.priceLabel)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Bitcoin Price")
            } footer: {
                if row.areLabelsBold {
                    Text("Live price — refreshes every 60s on the list screen")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(row.dateLabel)
        .navigationBarTitleDisplayMode(.inline)
    }
}
