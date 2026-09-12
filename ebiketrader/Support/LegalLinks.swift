//
//  LegalLinks.swift
//  ebiketrader
//

import SwiftUI

/// Apple requires the privacy policy to be reachable from inside the app, not
/// only from the App Store listing metadata — and a reviewer may never sign
/// in, so these appear on the sign-in screen as well as under Account.
enum Legal {
    static let privacy = URL(string: "https://ebiketrader.net/privacy")!
    static let terms = URL(string: "https://ebiketrader.net/terms")!
    static let support = URL(string: "https://ebiketrader.net/support")!
}

/// Compact one-line pair, for the bottom of the sign-in screen.
struct LegalLinksRow: View {
    var body: some View {
        HStack(spacing: 6) {
            Link("Privacy Policy", destination: Legal.privacy)
            Text("·")
            Link("Terms of Use", destination: Legal.terms)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
