//
//  ProgressOverlay.swift
//  ebiketrader
//

import SwiftUI

extension View {
    /// A blocking progress overlay for actions that can take real time.
    ///
    /// A spinner swapped into a button label is too easy to miss — it is one
    /// small glyph in one row, and an action that finishes quickly just makes
    /// it flicker. This dims and covers the content instead, so the state is
    /// unmistakable. The dimming layer is a real Color, which means it also
    /// swallows taps and makes a double-submit impossible.
    ///
    /// - Parameters:
    ///   - title: what is happening, in the present continuous.
    ///   - detail: optional second line, for step counts like "Photo 2 of 5".
    func progressOverlay(_ isActive: Bool, title: String, detail: String? = nil) -> some View {
        overlay {
            if isActive {
                ZStack {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()

                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.large)

                        Text(title)
                            .font(.subheadline.weight(.medium))

                        if let detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                // Keeps the card from jiggling as digits change.
                                .monospacedDigit()
                        }
                    }
                    .padding(24)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                }
            }
        }
        // Fades in, so a fast action reads as a deliberate beat not a flicker.
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}
