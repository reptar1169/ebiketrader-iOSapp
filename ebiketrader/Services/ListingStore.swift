//
//  ListingStore.swift
//  ebiketrader
//

import Combine
import Foundation
import FirebaseFirestore

enum ListingSort: String, CaseIterable, Identifiable, Hashable {
    case newest
    case priceAsc
    case priceDesc

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "Newest first"
        case .priceAsc: return "Price: low to high"
        case .priceDesc: return "Price: high to low"
        }
    }
}

/// The client-side half of the web app's filtering. Only `status` and the
/// sort order are sent to Firestore (see ListingStore.subscribe) — everything
/// here is applied to the page that comes back, which is what lets the whole
/// feed run on the two composite indexes the site already has.
struct ListingFilters: Equatable {
    var condition: Condition?
    var minPrice: Double?
    var maxPrice: Double?
    var brand: String?
    var state: String?

    var isActive: Bool {
        condition != nil || minPrice != nil || maxPrice != nil || brand != nil || state != nil
    }

    mutating func clear() {
        self = ListingFilters()
    }
}

extension Array where Element == Listing {
    /// Client-side filtering from subscribeListings() plus the homepage's text
    /// search (HomeClient.tsx) — same fields, same case-insensitive contains.
    func applying(_ filters: ListingFilters, search: String) -> [Listing] {
        var result = self

        if let brand = filters.brand {
            result = result.filter { $0.brand == brand }
        }
        if let condition = filters.condition {
            result = result.filter { $0.condition == condition }
        }
        if let minPrice = filters.minPrice {
            result = result.filter { $0.price >= minPrice }
        }
        if let maxPrice = filters.maxPrice {
            result = result.filter { $0.price <= maxPrice }
        }
        if let state = filters.state {
            result = result.filter { $0.state.caseInsensitiveCompare(state) == .orderedSame }
        }

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { listing in
                [listing.title, listing.brand, listing.model, listing.city, listing.state]
                    .joined(separator: " ")
                    .lowercased()
                    .contains(query)
            }
        }

        return result
    }
}

/// Live listings feed — a port of subscribeListings() in src/lib/listings.ts.
///
/// Firestore's callbacks already arrive on the main queue, so the @Published
/// properties below are safe to set straight from the listener.
final class ListingStore: ObservableObject {
    @Published private(set) var listings: [Listing] = []
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    /// Changing this re-runs the query. Sort is applied server-side alongside
    /// limit(300), so it decides *which* 300 listings come back, not just the
    /// order they arrive in — which is why it can't be done on the client.
    @Published var sort: ListingSort = .newest {
        didSet {
            guard oldValue != sort, registration != nil else { return }
            subscribe()
        }
    }

    private let status: ListingStatus?
    private let sellerId: String?
    private var registration: ListenerRegistration?

    /// - Parameters:
    ///   - status: nil means "any status" (used by My Listings, which shows
    ///     sold ones too). Defaults to active, like the website's browse feed.
    ///   - sellerId: restricts to one seller's listings.
    init(status: ListingStatus? = .active, sellerId: String? = nil) {
        self.status = status
        self.sellerId = sellerId
    }

    deinit {
        registration?.remove()
    }

    /// Safe to call from .onAppear — re-entering the view won't stack up
    /// duplicate listeners.
    func startIfNeeded() {
        guard registration == nil else { return }
        subscribe()
    }

    func stop() {
        registration?.remove()
        registration = nil
    }

    private func subscribe() {
        registration?.remove()
        isLoading = true

        var query: Query = Firestore.firestore().collection("listings")

        if let status {
            query = query.whereField("status", isEqualTo: status.rawValue)
        }
        if let sellerId {
            query = query.whereField("sellerId", isEqualTo: sellerId)
        }

        switch sort {
        case .newest:
            query = query.order(by: "createdAt", descending: true)
        case .priceAsc:
            query = query.order(by: "price", descending: false)
        case .priceDesc:
            query = query.order(by: "price", descending: true)
        }

        query = query.limit(to: 300)

        registration = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            self.isLoading = false

            if let error {
                self.errorMessage = error.localizedDescription
                return
            }

            self.errorMessage = nil
            self.listings = snapshot?.documents.map {
                Listing(id: $0.documentID, data: $0.data())
            } ?? []
        }
    }
}

/// Live view of a single listing, so the detail screen picks up a price edit
/// or a "mark as sold" while it's open. Mirrors subscribeListing().
final class ListingDetailStore: ObservableObject {
    @Published var listing: Listing
    /// Set when the listing is deleted out from under the screen.
    @Published private(set) var wasRemoved = false

    private var registration: ListenerRegistration?

    init(listing: Listing) {
        self.listing = listing
    }

    deinit {
        registration?.remove()
    }

    func startIfNeeded() {
        guard registration == nil else { return }
        registration = Firestore.firestore()
            .collection("listings")
            .document(listing.id)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                guard let data = snapshot.data() else {
                    self.wasRemoved = true
                    return
                }
                self.listing = Listing(id: snapshot.documentID, data: data)
            }
    }
}
