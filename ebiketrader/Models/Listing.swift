//
//  Listing.swift
//  ebiketrader
//

import Foundation

/// Mirrors CONDITIONS / CONDITION_LABELS in the website's src/lib/types.ts.
/// The raw values are the exact strings stored in Firestore — do not change
/// them without migrating existing listings.
enum Condition: String, CaseIterable, Identifiable, Hashable {
    case new
    case likeNew = "like-new"
    case excellent
    case good
    case fair
    case needsWork = "needs-work"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .new: return "New / never ridden"
        case .likeNew: return "Like new"
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .needsWork: return "Needs work"
        }
    }

    /// Fits on a listing card badge, where the full label wraps.
    var shortLabel: String {
        self == .new ? "New" : label
    }
}

/// Mirrors MOTOR_TYPES in src/lib/types.ts — free text in Firestore, but the
/// post form offers these.
let motorTypes = [
    "Hub motor (front)",
    "Hub motor (rear)",
    "Mid-drive",
    "Other / not sure",
]

/// How long a listing stays up after it's posted or renewed. Keep in sync
/// with LISTING_LIFETIME_DAYS in functions/index.js and src/lib/types.ts.
let listingLifetimeDays = 30
/// The owner is offered "Renew" once a live listing is this close to expiring.
let renewWindowDays = 7
private let dayMillis: Double = 24 * 60 * 60 * 1000

enum ListingStatus: String, Hashable {
    case active
    case sold
    /// Only ever set by the expireListings Cloud Function.
    case expired

    /// The overlay on the listing's photo; nil for a live listing.
    var badge: String? {
        switch self {
        case .active: return nil
        case .sold: return "SOLD"
        case .expired: return "EXPIRED"
        }
    }
}

struct Listing: Identifiable, Hashable {
    let id: String
    var title: String
    var brand: String
    var model: String
    var year: Int?
    var price: Double
    var condition: Condition
    var mileageMiles: Int?
    var batteryHealthPct: Int?
    var motorType: String
    var frameSize: String
    var wheelSize: String
    var color: String
    var listingDescription: String
    var city: String
    var state: String
    /// Geocoded server-side from city/state by the onListingWrite Cloud
    /// Function — never written by a client (firestore.rules enforces it).
    var lat: Double?
    var lng: Double?
    var photos: [String]
    var sellerId: String
    var sellerName: String
    var status: ListingStatus
    /// Maintained server-side by the favorite Cloud Function triggers; also
    /// read-only to clients per firestore.rules.
    var favoriteCount: Int
    /// Start of the current 30-day window: set on creation, reset by
    /// ListingWriter.renew. nil only on old listings not yet backfilled.
    var renewedAt: Double?
    /// Epoch milliseconds (see FirestoreValue.millis).
    var createdAt: Double?
    var updatedAt: Double?

    var locationLine: String {
        Format.location(city: city, state: state)
    }

    var primaryPhoto: URL? {
        guard let first = photos.first else { return nil }
        return URL(string: first)
    }

    /// "2022 Rad Power RadCity 5 Plus" — the human name for this bike, used
    /// where the seller's free-text title isn't wanted (share sheet subject,
    /// the brand/model link, the photo filename slug).
    var makeModel: String {
        [year.map(String.init), brand, model]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var webURL: URL? {
        URL(string: "https://ebiketrader.net/listing/\(id)")
    }

    /// When a live listing expires (epoch ms), or nil if it isn't counting down.
    var expiresAt: Double? {
        guard status == .active, let start = renewedAt ?? createdAt else { return nil }
        return start + Double(listingLifetimeDays) * dayMillis
    }

    /// Whole days until expiry, rounded up — 0 means today.
    var daysUntilExpiry: Int? {
        guard let expiresAt else { return nil }
        let remaining = expiresAt - Date().timeIntervalSince1970 * 1000
        return max(0, Int((remaining / dayMillis).rounded(.up)))
    }

    /// Expired, or live and inside the renew window. Sold listings come back
    /// through "Mark active", which renews them too.
    var canRenew: Bool {
        if status == .expired { return true }
        guard let days = daysUntilExpiry else { return false }
        return days <= renewWindowDays
    }

    /// "Expires in 3 days" for the owner; nil for sold listings.
    var expiryLine: String? {
        if status == .expired { return "Expired" }
        switch daysUntilExpiry {
        case nil: return nil
        case 0: return "Expires today"
        case 1: return "Expires in 1 day"
        case let days?: return "Expires in \(days) days"
        }
    }
}

extension Listing {
    /// Field-for-field port of fromDoc() in src/lib/listings.ts, including
    /// each fallback — so a listing renders identically in the app and on the
    /// web even when optional fields are missing.
    init(id: String, data: [String: Any]) {
        self.id = id
        self.title = FirestoreValue.string(data["title"])
        self.brand = FirestoreValue.string(data["brand"])
        self.model = FirestoreValue.string(data["model"])
        self.year = FirestoreValue.int(data["year"])
        self.price = FirestoreValue.double(data["price"]) ?? 0
        self.condition = Condition(rawValue: FirestoreValue.string(data["condition"])) ?? .good
        self.mileageMiles = FirestoreValue.int(data["mileageMiles"])
        self.batteryHealthPct = FirestoreValue.int(data["batteryHealthPct"])
        self.motorType = FirestoreValue.string(data["motorType"])
        self.frameSize = FirestoreValue.string(data["frameSize"])
        self.wheelSize = FirestoreValue.string(data["wheelSize"])
        self.color = FirestoreValue.string(data["color"])
        self.listingDescription = FirestoreValue.string(data["description"])
        self.city = FirestoreValue.string(data["city"])
        self.state = FirestoreValue.string(data["state"])
        self.lat = FirestoreValue.double(data["lat"])
        self.lng = FirestoreValue.double(data["lng"])
        self.photos = data["photos"] as? [String] ?? []
        self.sellerId = FirestoreValue.string(data["sellerId"])
        self.sellerName = FirestoreValue.string(data["sellerName"], default: "Seller")
        self.status = ListingStatus(rawValue: FirestoreValue.string(data["status"])) ?? .active
        self.favoriteCount = FirestoreValue.int(data["favoriteCount"]) ?? 0
        self.renewedAt = FirestoreValue.millis(data["renewedAt"])
        self.createdAt = FirestoreValue.millis(data["createdAt"])
        self.updatedAt = FirestoreValue.millis(data["updatedAt"])
    }
}
