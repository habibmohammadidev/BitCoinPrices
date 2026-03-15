//
//  ContentView.swift
//  BitconPrices
//
//  Created by Habibollah Mohammadi on 12.03.26.
//

import SwiftUI

struct ContentView: View {
    private let repository: BitcoinRepository

    init(repository: BitcoinRepository = LiveBitcoinRepository.live()) {
        self.repository = repository
    }

    var body: some View {
        PriceListView(viewModel: PriceListViewModel(repository: repository))
    }
}

#Preview {
    ContentView(repository: LiveBitcoinRepository.live())
}
