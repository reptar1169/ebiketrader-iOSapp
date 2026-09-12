//
//  MessageStore.swift
//  ebiketrader
//

import Combine
import Foundation
import FirebaseFirestore

/// Shared pieces of the messaging data model, ported from
/// src/lib/messages.ts. Kept in one place so the id scheme can't drift
/// between the app and the website — a mismatch would silently start a
/// second thread for a buyer who already had one.
/// Named ChatService rather than the more obvious "Messaging" because that
/// would shadow FirebaseMessaging's own Messaging class — a same-module type
/// wins over an imported one, which breaks push registration in any file that
/// imports both.
enum ChatService {
    static let collection = "conversations"

    /// Deterministic id: one thread per listing per buyer, on both clients.
    static func conversationId(listingId: String, buyerId: String) -> String {
        "\(listingId)_\(buyerId)"
    }

    /// Port of getOrCreateConversation(). Safe to call every time someone
    /// opens "message seller" — it only writes when the thread is new.
    @discardableResult
    static func getOrCreateConversation(
        listing: Listing,
        buyerId: String,
        buyerName: String
    ) async throws -> String {
        let id = conversationId(listingId: listing.id, buyerId: buyerId)
        let reference = Firestore.firestore().collection(collection).document(id)

        let existing = try await reference.getDocument()
        guard !existing.exists else { return id }

        // Firestore wants NSNull for an explicit null; an Optional bridged
        // through `as Any` arrives as a wrapped nil and is rejected.
        let photo: Any = listing.photos.isEmpty ? NSNull() : listing.photos[0]

        try await reference.setData([
            "listingId": listing.id,
            "listingTitle": listing.title,
            "listingPhoto": photo,
            "sellerId": listing.sellerId,
            "sellerName": listing.sellerName,
            "buyerId": buyerId,
            "buyerName": buyerName,
            "lastMessage": "",
            "lastMessageAt": FieldValue.serverTimestamp(),
            "lastSenderId": "",
            // The buyer is the one creating this thread, so it starts read
            // for them and unread for the seller.
            "buyerLastReadAt": FieldValue.serverTimestamp(),
            "sellerLastReadAt": NSNull(),
        ])
        return id
    }

    /// The summary for a thread the app is about to open, built from what a
    /// listing already knows rather than re-reading the doc that was just
    /// written. The inbox's live listener supplies the authoritative version
    /// moments later; this only needs to be right enough to render the
    /// header and address the right document.
    static func localSummary(
        listing: Listing,
        buyerId: String,
        buyerName: String
    ) -> ConversationSummary {
        ConversationSummary(
            id: conversationId(listingId: listing.id, buyerId: buyerId),
            listingId: listing.id,
            listingTitle: listing.title,
            listingPhoto: listing.photos.first,
            sellerId: listing.sellerId,
            sellerName: listing.sellerName,
            buyerId: buyerId,
            buyerName: buyerName,
            lastMessage: "",
            lastMessageAt: nil,
            lastSenderId: "",
            buyerLastReadAt: nil,
            sellerLastReadAt: nil
        )
    }

    /// Port of sendMessage(): append to the subcollection, then refresh the
    /// denormalized summary the inbox reads.
    static func send(conversationId: String, senderId: String, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let conversation = Firestore.firestore().collection(collection).document(conversationId)

        try await conversation.collection("messages").addDocument(data: [
            "senderId": senderId,
            "text": trimmed,
            "createdAt": FieldValue.serverTimestamp(),
        ])

        try await conversation.updateData([
            "lastMessage": trimmed,
            "lastMessageAt": FieldValue.serverTimestamp(),
            "lastSenderId": senderId,
        ])
    }

    /// Port of markConversationRead().
    static func markRead(conversationId: String, uid: String, buyerId: String) async throws {
        let field = uid == buyerId ? "buyerLastReadAt" : "sellerLastReadAt"
        try await Firestore.firestore()
            .collection(collection)
            .document(conversationId)
            .updateData([field: FieldValue.serverTimestamp()])
    }

    /// Port of deleteMessage(). firestore.rules only permits deleting your
    /// own messages; if the deleted one was the latest, the conversation's
    /// summary fields are rebuilt so the inbox doesn't keep previewing a
    /// message that no longer exists.
    static func delete(conversationId: String, messageId: String) async throws {
        let conversation = Firestore.firestore().collection(collection).document(conversationId)
        try await conversation.collection("messages").document(messageId).delete()

        let latest = try await conversation.collection("messages")
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .getDocuments()

        if let newest = latest.documents.first {
            let data = newest.data()
            // Carry the surviving message's own timestamp across, so the
            // inbox keeps sorting by when that message was actually sent.
            // A message still awaiting its serverTimestamp has none yet.
            var update: [String: Any] = [
                "lastMessage": FirestoreValue.string(data["text"]),
                "lastSenderId": FirestoreValue.string(data["senderId"]),
            ]
            if let timestamp = data["createdAt"] as? Timestamp {
                update["lastMessageAt"] = timestamp
            }
            try await conversation.updateData(update)
        } else {
            try await conversation.updateData(["lastMessage": "", "lastSenderId": ""])
        }
    }
}

/// The inbox. Firestore has no OR across fields, so this runs the same two
/// subscriptions the web app does (buyer side, seller side) and merges them.
final class ConversationStore: ObservableObject {
    @Published private(set) var conversations: [ConversationSummary] = []
    @Published private(set) var isLoading = true

    private var buyerRegistration: ListenerRegistration?
    private var sellerRegistration: ListenerRegistration?
    private var asBuyer: [ConversationSummary] = []
    private var asSeller: [ConversationSummary] = []
    private var uid: String?

    deinit {
        buyerRegistration?.remove()
        sellerRegistration?.remove()
    }

    func bind(to uid: String?) {
        guard uid != self.uid else { return }
        self.uid = uid

        buyerRegistration?.remove()
        sellerRegistration?.remove()
        buyerRegistration = nil
        sellerRegistration = nil
        asBuyer = []
        asSeller = []
        conversations = []

        guard let uid else {
            isLoading = false
            return
        }

        isLoading = true
        let collection = Firestore.firestore().collection(ChatService.collection)

        buyerRegistration = collection
            .whereField("buyerId", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                self.asBuyer = snapshot?.documents.map {
                    ConversationSummary(id: $0.documentID, data: $0.data())
                } ?? []
                self.merge()
            }

        sellerRegistration = collection
            .whereField("sellerId", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                self.asSeller = snapshot?.documents.map {
                    ConversationSummary(id: $0.documentID, data: $0.data())
                } ?? []
                self.merge()
            }
    }

    /// Threads with something you haven't read — drives the tab bar badge.
    func unreadCount() -> Int {
        guard let uid else { return 0 }
        return conversations.filter { $0.isUnread(for: uid) }.count
    }

    private func merge() {
        isLoading = false
        conversations = (asBuyer + asSeller)
            .sorted { ($0.lastMessageAt ?? 0) > ($1.lastMessageAt ?? 0) }
    }
}

/// One open thread.
final class ThreadStore: ObservableObject {
    @Published private(set) var messages: [Message] = []
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?

    let conversationId: String
    private var registration: ListenerRegistration?

    init(conversationId: String) {
        self.conversationId = conversationId
    }

    deinit {
        registration?.remove()
    }

    func startIfNeeded() {
        guard registration == nil else { return }
        registration = Firestore.firestore()
            .collection(ChatService.collection)
            .document(conversationId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.messages = snapshot?.documents.map {
                    Message(id: $0.documentID, data: $0.data())
                } ?? []
            }
    }

    /// Returns whether it went through, so the caller can put the draft back
    /// rather than swallowing what the person typed.
    @MainActor
    func send(text: String, senderId: String) async -> Bool {
        do {
            try await ChatService.send(conversationId: conversationId, senderId: senderId, text: text)
            errorMessage = nil
            return true
        } catch {
            errorMessage = Self.sendFailureMessage(for: error)
            return false
        }
    }

    /// A rejected write here almost always means the recipient has blocked
    /// the sender — firestore.rules refuses messages across a block.
    ///
    /// That is deliberately NOT said out loud. Telling someone they have been
    /// blocked invites exactly what blocking is meant to stop: a new account,
    /// or the argument moving somewhere with no block button. It is also the
    /// blocker's private business. Every major messaging product does the
    /// same thing — the message simply does not arrive. So the copy stays
    /// neutral and true, and the draft is handed back so nothing is lost.
    ///
    /// Genuine failures (offline, timeout) keep their real message, because
    /// there the person can actually do something about it. Matched on the
    /// numeric code rather than FirestoreErrorCode, which has shifted shape
    /// between Firebase major versions.
    private static func sendFailureMessage(for error: Error) -> String {
        let nsError = error as NSError
        let isPermissionDenied =
            nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7
        return isPermissionDenied
            ? "This message couldn't be sent."
            : error.localizedDescription
    }

    @MainActor
    func delete(_ message: Message) async {
        do {
            try await ChatService.delete(conversationId: conversationId, messageId: message.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
