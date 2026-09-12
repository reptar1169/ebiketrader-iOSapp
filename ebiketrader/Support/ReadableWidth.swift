//
//  ReadableWidth.swift
//  ebiketrader
//

import SwiftUI

extension View {
    /// Caps a content column's width on large screens and centres it.
    ///
    /// On a 13-inch iPad a full-width paragraph measures around a thousand
    /// points, which is roughly double the line length anyone reads
    /// comfortably. This keeps prose near the 60-75 characters per line that
    /// is comfortable, and is a no-op on a phone, where the cap is never
    /// reached.
    ///
    /// The two frames are deliberate: the first constrains, the second
    /// expands the constrained view's slot back to full width so it ends up
    /// centred rather than pinned to the leading edge.
    func readableWidth(_ maxWidth: CGFloat = 700) -> some View {
        self
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
