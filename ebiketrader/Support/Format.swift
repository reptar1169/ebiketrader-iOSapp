//
//  Format.swift
//  ebiketrader
//

import Foundation

/// Ports src/lib/format.ts from the website. The thresholds and wording are
/// copied deliberately rather than handed to RelativeDateTimeFormatter, so a
/// listing reads "3d ago" in the app and on the web instead of "3 days ago"
/// in one and something else in the other.
enum Format {
    private static let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let absoluteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    static func price(_ value: Double) -> String {
        priceFormatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    /// `millis` is epoch milliseconds — the same unit the web app's toMillis()
    /// produces, and what Listing/Message carry. nil (an unresolved
    /// serverTimestamp) formats as an empty string, same as on the web.
    static func relativeTime(_ millis: Double?) -> String {
        guard let millis, millis > 0 else { return "" }
        let date = Date(timeIntervalSince1970: millis / 1000)

        let diffSec = Int(Date().timeIntervalSince(date).rounded())
        let diffMin = Int((Double(diffSec) / 60).rounded())
        let diffHr = Int((Double(diffMin) / 60).rounded())
        let diffDay = Int((Double(diffHr) / 24).rounded())

        if diffSec < 60 { return "just now" }
        if diffMin < 60 { return "\(diffMin)m ago" }
        if diffHr < 24 { return "\(diffHr)h ago" }
        if diffDay < 7 { return "\(diffDay)d ago" }
        return absoluteDateFormatter.string(from: date)
    }

    /// "Austin, TX" — drops either half if it is blank.
    static func location(city: String, state: String) -> String {
        [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
