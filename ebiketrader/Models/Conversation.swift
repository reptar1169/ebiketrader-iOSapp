//
//  Conversation.swift
//  ebiketrader
//

import Foundation

/// Mirrors ConversationSummary in the website's src/lib/types.ts. The doc id
/// is always "{listingId}_{buyerId}" (see MessageStore.conversationId), which
/// is what keeps one buyer + one listing to a single thread on both clients.
struct ConversationSummary: Identifiable, Hashable {
    let id: String
    var listingId: String
    var listingTitle: String
    var listingPhoto: String?
    var sellerId: String
    var sellerName: String
    var buyerId: String
    var buyerName: String
    var lastMessage: String
    var lastMessageAt: Double?
    var lastSenderId: String
    /// When each side last opened the thread — null means never.
    var buyerLastReadAt: Double?
    var sellerLastReadAt: Double?

    /// Port of isUnreadForUser() in src/lib/messages.ts: there's a message
    /// you didn't send, and you haven't opened the thread since it arrived.
    func isUnread(for uid: String) -> Bool {
        guard let lastMessageAt, lastSenderId != uid else { return false }
        let lastReadAt = uid == buyerId ? buyerLastReadAt : sellerLastReadAt
        guard let lastReadAt else { return true }
        return lastMessageAt > lastReadAt
    }

    /// The name to show in the inbox — whoever isn't you.
    func otherPartyName(for uid: String) -> String {
        uid == buyerId ? sellerName : buyerName
    }

    var photoURL: URL? {
        guard let listingPhoto else { return nil }
        return URL(string: listingPhoto)
    }
}

extension ConversationSummary {
    /// Port of summaryFromDoc() in src/lib/messages.ts, fallbacks included.
    init(id: String, data: [String: Any]) {
        self.id = id
        self.listingId = FirestoreValue.string(data["listingId"])
        self.listingTitle = FirestoreValue.string(data["listingTitle"])
        self.listingPhoto = data["listingPhoto"] as? String
        self.sellerId = FirestoreValue.string(data["sellerId"])
        self.sellerName = FirestoreValue.string(data["sellerName"], default: "Seller")
        self.buyerId = FirestoreValue.string(data["buyerId"])
        self.buyerName = FirestoreValue.string(data["buyerName"], default: "Buyer")
        self.lastMessage = FirestoreValue.string(data["lastMessage"])
        self.lastMessageAt = FirestoreValue.millis(data["lastMessageAt"])
        self.lastSenderId = FirestoreValue.string(data["lastSenderId"])
        self.buyerLastReadAt = FirestoreValue.millis(data["buyerLastReadAt"])
        self.sellerLastReadAt = FirestoreValue.millis(data["sellerLastReadAt"])
    }
}

struct Message: Identifiable, Hashable {
    let id: String
    var senderId: String
    var text: String
    var createdAt: Double?

    init(id: String, data: [String: Any]) {
        self.id = id
        self.senderId = FirestoreValue.string(data["senderId"])
        self.text = FirestoreValue.string(data["text"])
        self.createdAt = FirestoreValue.millis(data["createdAt"])
    }
}
