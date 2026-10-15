//
//  ReportConversationSheet.swift
//  ebiketrader
//

import SwiftUI

/// Reporting the thread rather than one message: a scam is a pattern across
/// several messages, and picking out the single bad one is work the person
/// being scammed should not have to do.
struct ReportConversationSheet: View {
    let conversation: ConversationSummary

    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        let uid = auth.uid ?? ""
        let other = conversation.buyerId == uid ? conversation.sellerId : conversation.buyerId

        ReportSheet(
            title: "Report conversation",
            footnote: "We review every report, and we can see the messages in this thread. You can also block this person so they can't message you again.",
            identity: [
                "kind": "conversation",
                "conversationId": conversation.id,
                "reportedUserId": other,
                // The listing the thread is about. Required by
                // firestore.rules, and it gives the admin queue something to
                // name the report by.
                "listingId": conversation.listingId,
                "listingTitle": conversation.listingTitle,
                "listingSellerId": conversation.sellerId,
                "reporterId": uid,
            ]
        )
    }
}
