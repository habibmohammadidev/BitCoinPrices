//
//  NumberFormatter.swift
//  BitconPrices
//
//  Created by Habibollah Mohammadi on 13.03.26.
//

import Foundation

extension NumberFormatter {
    static var currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.maximumFractionDigits = 0
        return f
    }()
}
