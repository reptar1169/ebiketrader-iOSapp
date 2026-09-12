//
//  MyListingsView.swift
//  ebiketrader
//

import SwiftUI

/// Everything this seller has posted, sold ones included — which is why it
/// passes status: nil rather than the browse feed's .active.
struct MyListingsView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        Group {
            if let uid = auth.uid {
                MyListingsList(sellerId: uid)
            } else {
                ContentUnavailableView(
                    "Not signed in",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
            }
        }
        .navigationTitle("My listings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Split out so the store can be created with the seller id already known —
/// @StateObject is initialized once, and re-pointing it after the fact would
/// mean rebuilding the query anyway.
private struct MyListingsList: View {
    @StateObject private var store: ListingStore

    init(sellerId: String) {
        _store = StateObject(wrappedValue: ListingStore(status: nil, sellerId: sellerId))
    }

    var body: some View {
        Group {
            if store.isLoading && store.listings.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.listings.isEmpty {
                ContentUnavailableView {
                    Label("No listings yet", systemImage: "bicycle")
                } description: {
                    Text("Bikes you post will show up here.")
                }
            } else {
                List(store.listings) { listing in
                    NavigationLink {
                        ListingDetailView(listing: listing)
                    } label: {
                        ListingRow(listing: listing)
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear { store.startIfNeeded() }
    }
}

/// Compact horizontal row — the list counterpart to ListingCardView.
struct ListingRow: View {
    let listing: Listing

    var body: some View {
        HStack(spacing: 12) {
            ListingPhotoBox(url: listing.primaryPhoto, cornerRadius: 8)
                .frame(width: 72)

            VStack(alignment: .leading, spacing: 3) {
                Text(listing.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(Format.price(listing.price))
                        .foregroundStyle(Theme.brandDark)
                    if listing.status == .sold {
                        Text("SOLD")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                    }
                }
                .font(.footnote)
                Text(listing.locationLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
