//
//  InboxView.swift
//  ebiketrader
//

import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var conversations: ConversationStore
    @EnvironmentObject private var push: PushService
    @EnvironmentObject private var blocks: BlockStore

    @State private var openConversation: ConversationSummary?
    @State private var showSignIn = false

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isSignedIn {
                    ContentUnavailableView {
                        Label("Sign in to see messages", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Your conversations with buyers and sellers live here.")
                    } actions: {
                        Button("Sign in") { showSignIn = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if conversations.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visibleConversations.isEmpty {
                    ContentUnavailableView {
                        Label("No messages yet", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Message a seller from any listing to start a conversation.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Messages")
            .navigationDestination(item: $openConversation) { conversation in
                ThreadView(conversation: conversation)
            }
        }
        .signInSheet(isPresented: $showSignIn)
        .task {
            // Asked here rather than at launch: iOS shows this prompt exactly
            // once, and it makes far more sense on the screen that's about to
            // start notifying you.
            await push.refreshAuthorizationStatus()
            if auth.isSignedIn && push.authorizationStatus == .notDetermined {
                await push.requestAuthorization()
            }
        }
        .onChange(of: push.pendingConversationId) { _, _ in
            openPendingConversation()
        }
        .onChange(of: conversations.conversations) { _, _ in
            // The tap may arrive before the inbox listener has loaded, so
            // retry once the list fills in.
            openPendingConversation()
        }
        .onAppear(perform: openPendingConversation)
    }

    private func openPendingConversation() {
        guard let pending = push.pendingConversationId else { return }
        guard let match = conversations.conversations.first(where: { $0.id == pending }) else { return }
        openConversation = match
        push.pendingConversationId = nil
    }

    /// A blocked person's thread disappears from the inbox. The documents
    /// stay put — firestore.rules simply stops either side adding to them.
    private var visibleConversations: [ConversationSummary] {
        let me = auth.uid ?? ""
        return conversations.conversations.filter { conversation in
            let other = conversation.buyerId == me ? conversation.sellerId : conversation.buyerId
            return !blocks.isBlocked(other)
        }
    }

    private var list: some View {
        List(visibleConversations) { conversation in
            NavigationLink {
                ThreadView(conversation: conversation)
            } label: {
                ConversationRow(
                    conversation: conversation,
                    uid: auth.uid ?? "",
                    isUnread: conversation.isUnread(for: auth.uid ?? "")
                )
            }
        }
        .listStyle(.plain)
    }
}

private struct ConversationRow: View {
    let conversation: ConversationSummary
    let uid: String
    let isUnread: Bool

    var body: some View {
        HStack(spacing: 12) {
            ListingPhotoBox(url: conversation.photoURL, cornerRadius: 8)
                .frame(width: 56)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.otherPartyName(for: uid))
                        .font(.subheadline.weight(isUnread ? .bold : .medium))
                    Spacer(minLength: 8)
                    Text(Format.relativeTime(conversation.lastMessageAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(conversation.listingTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(conversation.lastMessage.isEmpty ? "No messages yet" : conversation.lastMessage)
                    .font(.footnote)
                    .foregroundStyle(isUnread ? .primary : .secondary)
                    .lineLimit(1)
            }

            if isUnread {
                Circle()
                    .fill(Theme.brand)
                    .frame(width: 9, height: 9)
            }
        }
        .padding(.vertical, 4)
    }
}
