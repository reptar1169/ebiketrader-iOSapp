//
//  Slug.swift
//  ebiketrader
//

import Foundation

/// Port of src/lib/slug.ts. Both clients have to produce byte-identical
/// slugs: they name the photo files in Storage, and the website's
/// /brand/[brand]/[model] catalog pages are keyed off the same function, so a
/// bike listed from the phone has to land on the same page as one listed from
/// the web.
func slugify(_ text: String) -> String {
    // .diacriticInsensitive is the equivalent of the web's NFKD normalize
    // followed by stripping the U+0300-U+036F combining marks.
    let folded = text
        .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
        .lowercased()

    var result = ""
    var pendingDash = false

    for character in folded {
        if character.isASCII && (character.isLetter || character.isNumber) {
            if pendingDash && !result.isEmpty { result.append("-") }
            pendingDash = false
            result.append(character)
        } else {
            // Collapses any run of non-alphanumerics into a single dash, and
            // never emits a leading or trailing one.
            pendingDash = true
        }
    }

    return result
}

/// Port of buildPhotoSlugBase() in src/lib/listings.ts — "2022-rad-power-
/// radcity-5-plus". This is what gives an uploaded photo a filename Google
/// Images can actually rank, instead of an opaque timestamp.
func buildPhotoSlugBase(year: Int?, brand: String, model: String) -> String {
    let parts = [year.map(String.init) ?? "", brand, model]
        .map(slugify)
        .filter { !$0.isEmpty }
    return parts.isEmpty ? "ebike" : parts.joined(separator: "-")
}

/// Mirrors the web's `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
/// — keeps filenames collision-free and non-guessable even though the
/// readable part is shared across a listing's photos.
func photoUniqueId() -> String {
    let millis = Int(Date().timeIntervalSince1970 * 1000)
    let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
    let suffix = String((0..<6).map { _ in alphabet.randomElement() ?? "0" })
    return "\(millis)-\(suffix)"
}
