//
//  FirestoreValue.swift
//  ebiketrader
//

import Foundation
import FirebaseFirestore

/// Small readers for the untyped `[String: Any]` a Firestore document hands
/// back. Everything goes through these rather than Codable on purpose: the
/// website writes these documents with plain object literals and has added
/// fields over time (favoriteCount, lat/lng), so a strict decoder would fail
/// on perfectly good older listings. This mirrors the hand-written fromDoc()
/// in src/lib/listings.ts — every field optional-tolerant, with the same
/// fallbacks.
enum FirestoreValue {
    /// Firestore returns every number as NSNumber, so casting straight to Int
    /// fails whenever the stored value happens to be a Double (a price saved
    /// as 1200.0 rather than 1200) and vice versa. Going through NSNumber
    /// accepts either.
    static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    static func string(_ value: Any?, default fallback: String = "") -> String {
        value as? String ?? fallback
    }

    /// Epoch milliseconds, matching the `number | null` the web app's
    /// toMillis() produces. A serverTimestamp() that the server hasn't
    /// resolved yet arrives as nil here exactly as it does on the web, so
    /// "just posted" content simply has no timestamp for a moment.
    static func millis(_ value: Any?) -> Double? {
        guard let timestamp = value as? Timestamp else { return nil }
        return Double(timestamp.seconds) * 1000 + Double(timestamp.nanoseconds) / 1_000_000
    }
}
