//
//  ListingWriter.swift
//  ebiketrader
//

import Foundation
import UIKit
import FirebaseFirestore
import FirebaseStorage

/// The editable half of a listing — everything a seller types. Deliberately
/// excludes sellerId/status/favoriteCount/lat/lng/timestamps: those are set
/// once at creation or maintained server-side, and firestore.rules rejects a
/// client that tries to change them.
struct ListingInput: Equatable {
    var title = ""
    var brand = ""
    var model = ""
    var year: Int?
    var price: Double?
    var condition: Condition = .good
    var mileageMiles: Int?
    var batteryHealthPct: Int?
    var motorType = ""
    var frameSize = ""
    var wheelSize = ""
    var color = ""
    var listingDescription = ""
    var city = ""
    var state = ""

    /// Same three the website's ListingForm requires.
    var validationError: String? {
        if title.trimmed.isEmpty || brand.trimmed.isEmpty || price == nil {
            return "Title, brand, and price are required."
        }
        if let price, price < 0 || !price.isFinite {
            return "Enter a valid price."
        }
        return nil
    }

    init() {}

    /// Seeds the form when editing an existing listing.
    init(from listing: Listing) {
        title = listing.title
        brand = listing.brand
        model = listing.model
        year = listing.year
        price = listing.price
        condition = listing.condition
        mileageMiles = listing.mileageMiles
        batteryHealthPct = listing.batteryHealthPct
        motorType = listing.motorType
        frameSize = listing.frameSize
        wheelSize = listing.wheelSize
        color = listing.color
        listingDescription = listing.listingDescription
        city = listing.city
        state = listing.state
    }

    /// Firestore payload. Optional numbers go out as NSNull rather than being
    /// omitted, matching what the web form writes — the readers on both sides
    /// treat a missing field and a null one the same, but keeping the shape
    /// identical means a listing edited in one client doesn't look different
    /// in the other.
    func firestoreData() -> [String: Any] {
        [
            "title": title.trimmed,
            "brand": brand.trimmed,
            "model": model.trimmed,
            "year": year.map { $0 as Any } ?? NSNull(),
            "price": price ?? 0,
            "condition": condition.rawValue,
            "mileageMiles": mileageMiles.map { $0 as Any } ?? NSNull(),
            "batteryHealthPct": batteryHealthPct.map { $0 as Any } ?? NSNull(),
            "motorType": motorType.trimmed,
            "frameSize": frameSize.trimmed,
            "wheelSize": wheelSize.trimmed,
            "color": color.trimmed,
            "description": listingDescription.trimmed,
            "city": city.trimmed,
            "state": state.trimmed,
        ]
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// One photo in the seller's chosen order — port of PhotoPlanItem in
/// src/lib/types.ts. The array's order is the saved `photos` order, which is
/// what lets a freshly shot photo be dragged ahead of an existing one.
enum PhotoPlanItem: Identifiable, Hashable {
    case existing(url: String)
    case new(id: UUID, image: UIImage)

    var id: String {
        switch self {
        case .existing(let url): return url
        case .new(let id, _): return id.uuidString
        }
    }

    var existingURL: String? {
        if case .existing(let url) = self { return url }
        return nil
    }

    var newImage: UIImage? {
        if case .new(_, let image) = self { return image }
        return nil
    }
}

extension Array where Element == PhotoPlanItem {
    /// Appends a freshly shot or picked image, respecting the photo cap.
    /// Returns false when there was no room left.
    @discardableResult
    mutating func appendPhoto(_ image: UIImage) -> Bool {
        guard count < ListingWriter.maxPhotos else { return false }
        append(.new(id: UUID(), image: image))
        return true
    }
}

enum ListingWriter {
    static let maxPhotos = 8

    /// Phone photos run 4-12MB each; Storage caps a single upload at 15MB
    /// (storage.rules) and every byte is also the buyer's data plan on the
    /// way back down. 1600px on the long edge is still more than any view in
    /// the app or on the website renders at.
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > 0 else { return nil }

        let scale = min(1, maxDimension / longEdge)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Port of uploadListingPhotos(). Filenames are
    /// "{slugBase}-{index}-{uniqueId}.jpg" under
    /// listing-photos/{uid}/{listingId}/, exactly as on the web.
    private static func upload(
        images: [UIImage],
        uid: String,
        listingId: String,
        slugBase: String,
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> [String] {
        var urls: [String] = []

        for (offset, image) in images.enumerated() {
            progress?(offset, images.count)

            guard let data = jpegData(from: image) else { continue }

            let name = "\(slugBase)-\(offset + 1)-\(photoUniqueId()).jpg"
            let reference = Storage.storage()
                .reference()
                .child("listing-photos/\(uid)/\(listingId)/\(name)")

            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"

            _ = try await reference.putDataAsync(data, metadata: metadata)
            let url = try await reference.downloadURL()
            urls.append(url.absoluteString)
        }

        progress?(images.count, images.count)
        return urls
    }

    /// Port of resolvePhotoPlan(): uploads whatever is new, passes existing
    /// URLs through untouched, and returns them all in plan order — so a
    /// photo added during this edit can sit first in the saved array rather
    /// than always being appended after the existing ones.
    private static func resolve(
        plan: [PhotoPlanItem],
        uid: String,
        listingId: String,
        input: ListingInput,
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> [String] {
        let newImages = plan.compactMap(\.newImage)

        let uploaded: [String]
        if newImages.isEmpty {
            uploaded = []
        } else {
            uploaded = try await upload(
                images: newImages,
                uid: uid,
                listingId: listingId,
                slugBase: buildPhotoSlugBase(year: input.year, brand: input.brand, model: input.model),
                progress: progress
            )
        }

        var nextUpload = 0
        return plan.compactMap { item -> String? in
            if let url = item.existingURL { return url }
            defer { nextUpload += 1 }
            return nextUpload < uploaded.count ? uploaded[nextUpload] : nil
        }
    }

    /// Port of createListing(): the document is created first so photos can
    /// be namespaced under its id, then the URLs are attached in a follow-up
    /// update.
    static func create(
        input: ListingInput,
        sellerId: String,
        sellerName: String,
        plan: [PhotoPlanItem],
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> String {
        var data = input.firestoreData()
        data["photos"] = [String]()
        data["sellerId"] = sellerId
        data["sellerName"] = sellerName
        // No sellerEmail: listing documents are world-readable per
        // firestore.rules, so anything written here is public. The address
        // stays on the private users/{uid} document.
        data["status"] = ListingStatus.active.rawValue
        // firestore.rules requires this to be exactly 0 on create, and lat/lng
        // to be absent — they're filled in by the geocoding Cloud Function.
        data["favoriteCount"] = 0
        data["createdAt"] = FieldValue.serverTimestamp()
        data["updatedAt"] = FieldValue.serverTimestamp()

        let reference = try await Firestore.firestore().collection("listings").addDocument(data: data)

        if !plan.isEmpty {
            let photos = try await resolve(
                plan: plan,
                uid: sellerId,
                listingId: reference.documentID,
                input: input,
                progress: progress
            )
            try await reference.updateData([
                "photos": photos,
                "updatedAt": FieldValue.serverTimestamp(),
            ])
        }

        return reference.documentID
    }

    /// Port of updateListing(). Never touches sellerId, favoriteCount or
    /// lat/lng — firestore.rules rejects the whole write if any of them move.
    static func update(
        listingId: String,
        uid: String,
        input: ListingInput,
        plan: [PhotoPlanItem],
        progress: ((Int, Int) -> Void)? = nil
    ) async throws {
        let photos = try await resolve(
            plan: plan,
            uid: uid,
            listingId: listingId,
            input: input,
            progress: progress
        )

        var data = input.firestoreData()
        data["photos"] = photos
        data["updatedAt"] = FieldValue.serverTimestamp()

        try await Firestore.firestore()
            .collection("listings")
            .document(listingId)
            .updateData(data)
    }

    static func setStatus(listingId: String, status: ListingStatus) async throws {
        try await Firestore.firestore()
            .collection("listings")
            .document(listingId)
            .updateData([
                "status": status.rawValue,
                "updatedAt": FieldValue.serverTimestamp(),
            ])
    }

    /// Port of deleteListing(): the document first, then best-effort photo
    /// cleanup — a photo that's already gone shouldn't fail the delete.
    static func delete(listingId: String, photoURLs: [String]) async throws {
        try await Firestore.firestore().collection("listings").document(listingId).delete()

        for url in photoURLs {
            do {
                try await Storage.storage().reference(forURL: url).delete()
            } catch {
                continue
            }
        }
    }
}
