//
//  ListingCardView.swift
//  ebiketrader
//

import SwiftUI

/// The grid cell — the app's answer to ListingCard.tsx on the website.
struct ListingCardView: View {
    let listing: Listing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ListingPhotoBox(url: listing.primaryPhoto)
                .overlay(alignment: .topLeading) {
                    if listing.status == .sold {
                        Text("SOLD")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.75), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }

            Text(Format.price(listing.price))
                .font(.headline)
                .foregroundStyle(Theme.brandDark)

            Text(listing.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(listing.locationLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
