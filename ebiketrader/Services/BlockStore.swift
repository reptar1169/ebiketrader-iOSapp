//
//  BlockStore.swift
//  ebiketrader
//

import Combine
import Foundation
import FirebaseFirestore

struct BlockedUser: Identifiable, Hashable {
    /// The blocked user's uid — also the document id.
    let id: String
    var displayName: String
    var createdAt: Double?
}

/// Who you have blocked, at users/{uid}/blocked/{blockedUid}.
///
/// The client filters blocked people out of the feed and the inbox, but that
/// is only the cosmetic half: firestore.rules also refuses to accept a
/// message in either direction across a block, so hiding here can't be worked
/// around by talking to the database directly.
final class BlockStore: ObservableObject {
    @Published private(set) var blocked: [BlockedUser] = []

    private var registration: ListenerRegistration?
    private var uid: String?

    deinit {
        registration?.remove()
    }

    var blockedIds: Set<String> {
        Set(blocked.map(\.id))
    }

    func isBlocked(_ userId: String) -> Bool {
        blocked.contains { $0.id == userId }
    }

    func bind(to uid: String?) {
        guard uid != self.uid else { return }
        self.uid = uid

        registration?.remove()
        registration = nil
        blocked = []

        guard let uid else { return }

        registration = collection(for: uid)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                self.blocked = snapshot.documents.map { document in
                    let data = document.data()
                    return BlockedUser(
                        id: document.documentID,
                        displayName: FirestoreValue.string(data["displayName"], default: "This user"),
                        createdAt: FirestoreValue.millis(data["createdAt"])
                    )
                }
            }
    }

    /// The display name is denormalised in so the Blocked list can name
    /// people without reading their profiles, which the rules wouldn't allow
    /// anyway — users/{uid} is readable only by its owner.
    func block(userId: String, displayName: String) async throws {
        guard let uid, userId != uid else { return }
        try await collection(for: uid).document(userId).setData([
            "displayName": displayName,
            "createdAt": FieldValue.serverTimestamp(),
        ])
    }

    func unblock(userId: String) async throws {
        guard let uid else { return }
        try await collection(for: uid).document(userId).delete()
    }

    private func collection(for uid: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("blocked")
    }
}
