//
//  Theme.swift
//  ebiketrader
//

import SwiftUI

extension Color {
    /// 0xRRGGBB, so the constants below can be read against the website's
    /// globals.css at a glance.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// The brand colors from ebiketrader.net (--brand / --brand-dark in
/// src/app/globals.css) so the app and the site read as one product.
///
/// Deliberately *only* the accent colors: the website is light-only and pins
/// its surfaces to an off-white, but an iOS app that ignores dark mode looks
/// broken, so backgrounds and text here use the system semantic colors and
/// adapt on their own.
enum Theme {
    static let brand = Color(hex: 0x0891B2)
    static let brandDark = Color(hex: 0x0E7490)

    /// Tinted fill behind photos while they load, and behind cards.
    static let placeholder = Color(.secondarySystemBackground)
}
