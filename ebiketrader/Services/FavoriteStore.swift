//
//  FavoriteStore.swift
//  ebiketrader
//

import Combine
import Foundation
import FirebaseFirestore

/// Saved listings, living at users/{uid}/favorites/{listingId} — the same
/// private-per-user subcollection the website writes (src/lib/favorites.ts),
/// so a bike saved on the phone shows up saved on the web and vice versa.
///
/// The actual favoriteCount on each listing is maintained by Cloud Function
/// triggers, not here; firestore.rules blocks clients from touching it.
final class FavoriteStore: ObservableObject {
    @Published private(set) var favoriteIds: Set<String> = []

    private var registration: ListenerRegistration?
    private var uid: String?

    deinit {
        registration?.remove()
    }

    /// Re-points at a different signed-in user, or clears on sign-out.
    func bind(to uid: String?) {
        guard uid != self.uid else { return }
        self.uid = uid

        registration?.remove()
        registration = nil
        favoriteIds = []

        guard let uid else { return }

        registration = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("favorites")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.favoriteIds = Set(snapshot.documents.map(\.documentID))
            }
    }

    func isFavorite(_ listingId: String) -> Bool {
        favoriteIds.contains(listingId)
    }

    /// Optimistic: the heart fills instantly and the snapshot listener
    /// confirms a moment later. On failure the listener's next emission puts
    /// it back, since Firestore stays the source of truth.
    func toggle(_ listingId: String) {
        guard let uid else { return }

        let document = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("favorites")
            .document(listingId)

        if favoriteIds.contains(listingId) {
            favoriteIds.remove(listingId)
            document.delete()
        } else {
            favoriteIds.insert(listingId)
            document.setData([
                "listingId": listingId,
                "createdAt": FieldValue.serverTimestamp(),
            ])
        }
    }
}
