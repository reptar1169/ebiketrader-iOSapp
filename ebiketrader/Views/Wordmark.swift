//
//  Wordmark.swift
//  ebiketrader
//

import SwiftUI

/// The eBikeTrader lockup: the badge mark, then "eBike", an amber bolt, and
/// "Trader" in brand teal.
///
/// Ported from the website's Navbar.tsx rather than exported as a PNG, for
/// three reasons: it stays sharp at any size, it scales with the badge
/// parameter instead of needing @2x/@3x variants, and the "eBike" half can
/// use .primary so it turns white in dark mode — a flattened image would
/// stay near-black and vanish against the app's dark background.
struct Wordmark: View {
    var badgeSize: CGFloat = 32
    var fontSize: CGFloat = 20

    var body: some View {
        HStack(spacing: badgeSize * 0.25) {
            badge

            HStack(spacing: 0) {
                Text("eBike")
                    .foregroundStyle(.primary)

                BoltGlyph()
                    // amber-500, as on the web.
                    .fill(Color(hex: 0xF59E0B))
                    .frame(width: fontSize * 0.6, height: fontSize * 0.95)

                Text("Trader")
                    .foregroundStyle(Theme.brand)
            }
            .font(.system(size: fontSize, weight: .bold))
            // tracking-tighter on the web.
            .tracking(-0.5)
        }
    }

    private var badge: some View {
        BikeMark()
            .scaled(to: badgeSize * 0.6875) // 22/32, the web's ratio
            .frame(width: badgeSize, height: badgeSize)
            .background(
                Theme.brand,
                in: RoundedRectangle(cornerRadius: badgeSize * 0.25, style: .continuous)
            )
    }
}

private extension View {
    /// Draws a 48-unit design at `size`. scaleEffect takes the stroke widths
    /// with it, which is what keeps the mark identical to the SVG at every
    /// size rather than growing spindly as it scales up.
    func scaled(to size: CGFloat) -> some View {
        let scale = size / 48
        return self
            .frame(width: 48, height: 48)
            .scaleEffect(scale)
            .frame(width: size, height: size)
    }
}

/// The bike-and-bolt mark, in the same 48-unit space as the website's
/// icon.tsx / apple-icon.tsx and this app's AppIcon.
private struct BikeMark: View {
    private static let spoke = Color(hex: 0x5FC4D6)
    private static let boltFill = Color(hex: 0xFBBF24)
    private static let boltEdge = Color(hex: 0x0E7490)

    private static let frameStroke = StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)

    var body: some View {
        ZStack {
            // Wheels.
            wheel(x: 13)
            wheel(x: 35)

            // Frame, seat tube and down tube.
            Path { path in
                path.move(to: CGPoint(x: 13, y: 33))
                path.addLine(to: CGPoint(x: 23, y: 33))
                path.addLine(to: CGPoint(x: 19, y: 14))
                path.addLine(to: CGPoint(x: 31, y: 14))
                path.addLine(to: CGPoint(x: 35, y: 33))
                path.move(to: CGPoint(x: 23, y: 33))
                path.addLine(to: CGPoint(x: 31, y: 14))
            }
            .stroke(Self.spoke, style: Self.frameStroke)

            // Saddle.
            Path { path in
                path.move(to: CGPoint(x: 15.5, y: 13))
                path.addLine(to: CGPoint(x: 22.5, y: 13))
            }
            .stroke(Self.spoke, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

            // Stem and handlebar.
            Path { path in
                path.move(to: CGPoint(x: 31, y: 14))
                path.addLine(to: CGPoint(x: 31, y: 9))
                path.move(to: CGPoint(x: 27, y: 9))
                path.addLine(to: CGPoint(x: 33, y: 9))
            }
            .stroke(Self.spoke, style: Self.frameStroke)

            // The bolt, across the whole mark.
            boltPath.fill(Self.boltFill)
            boltPath.stroke(Self.boltEdge, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
        }
    }

    private func wheel(x: CGFloat) -> some View {
        Circle()
            .stroke(Self.spoke, lineWidth: 2.4)
            .frame(width: 14, height: 14)
            .position(x: x, y: 33)
    }

    private var boltPath: Path {
        Path { path in
            path.move(to: CGPoint(x: 25.9, y: 5.5))
            path.addLine(to: CGPoint(x: 7.4, y: 27.7))
            path.addLine(to: CGPoint(x: 24, y: 27.7))
            path.addLine(to: CGPoint(x: 22.2, y: 42.5))
            path.addLine(to: CGPoint(x: 40.7, y: 20.3))
            path.addLine(to: CGPoint(x: 24, y: 20.3))
            path.closeSubpath()
        }
    }
}

/// The small bolt that sits between "eBike" and "Trader". Its own 14x22 box,
/// which hugs the shape — the website notes that forcing it square
/// letterboxes it and reintroduces a gap that no amount of zero margin fixes.
private struct BoltGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 14
        let scaleY = rect.height / 22
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }

        var path = Path()
        path.move(to: point(8, 0))
        path.addLine(to: point(1, 12))
        path.addLine(to: point(6, 12))
        path.addLine(to: point(4, 22))
        path.addLine(to: point(14, 8))
        path.addLine(to: point(8, 8))
        path.closeSubpath()
        return path
    }
}
