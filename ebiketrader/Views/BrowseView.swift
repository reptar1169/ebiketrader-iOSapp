//
//  BrowseView.swift
//  ebiketrader
//

import SwiftUI

struct BrowseView: View {
    @StateObject private var store = ListingStore()
    @EnvironmentObject private var blocks: BlockStore

    @State private var search = ""
    @State private var filters = ListingFilters()
    @State private var showFilters = false

    private var visible: [Listing] {
        store.listings
            .filter { !blocks.isBlocked($0.sellerId) }
            .applying(filters, search: search)
    }

    private var availableBrands: [String] {
        Array(Set(store.listings.map(\.brand).filter { !$0.isEmpty })).sorted()
    }

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("eBikeTrader")
                .navigationDestination(for: Listing.self) { listing in
                    ListingDetailView(listing: listing)
                }
                .searchable(text: $search, prompt: "Search by brand, model, or city")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showFilters = true
                        } label: {
                            Image(systemName: filters.isActive
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Sort", selection: $store.sort) {
                                ForEach(ListingSort.allCases) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                    }
                }
                .sheet(isPresented: $showFilters) {
                    FilterSheet(filters: $filters, availableBrands: availableBrands)
                }
        }
        .onAppear { store.startIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.errorMessage {
            ContentUnavailableView {
                Label("Couldn't load listings", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else if store.isLoading && store.listings.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visible.isEmpty {
            ContentUnavailableView {
                Label("No listings match", systemImage: "bicycle")
            } description: {
                Text(store.listings.isEmpty
                     ? "Nothing is listed right now — check back soon."
                     : "Try clearing your search or filters.")
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(visible) { listing in
                        NavigationLink(value: listing) {
                            ListingCardView(listing: listing)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
    }
}
