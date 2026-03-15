//
//  DateFormatterHelper.swift
//  BitconPrices
//
//  Created by Habibollah Mohammadi on 13.03.26.
//

import Foundation

extension DateFormatter {
    static var short: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }

    static var detailed: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }
}
