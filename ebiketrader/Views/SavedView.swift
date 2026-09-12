//
//  SavedView.swift
//  ebiketrader
//

import SwiftUI

/// Saved listings. The favorites subcollection stores ids only (matching the
/// website), so this intersects them with the live browse feed rather than
/// fetching each listing one at a time.
struct SavedView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var favorites: FavoriteStore
    @StateObject private var store = ListingStore(status: nil)

    private var saved: [Listing] {
        store.listings.filter { favorites.isFavorite($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isSignedIn {
                    ContentUnavailableView {
                        Label("Sign in to save listings", systemImage: "heart")
                    } description: {
                        Text("Tap the heart on any listing to keep it here.")
                    }
                } else if store.isLoading && store.listings.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if saved.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing saved yet", systemImage: "heart")
                    } description: {
                        Text("Tap the heart on a listing and it'll show up here.")
                    }
                } else {
                    List(saved) { listing in
                        NavigationLink {
                            ListingDetailView(listing: listing)
                        } label: {
                            ListingRow(listing: listing)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Saved")
        }
        .onAppear { store.startIfNeeded() }
    }
}
