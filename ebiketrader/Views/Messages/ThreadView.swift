//
//  ThreadView.swift
//  ebiketrader
//

import SwiftUI

struct ThreadView: View {
    let conversation: ConversationSummary

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var blocks: BlockStore
    @StateObject private var store: ThreadStore
    @State private var draft = ""
    @State private var pendingDeletion: Message?
    @State private var confirmBlock = false
    @State private var blockError: String?

    @Environment(\.dismiss) private var dismiss

    init(conversation: ConversationSummary) {
        self.conversation = conversation
        _store = StateObject(wrappedValue: ThreadStore(conversationId: conversation.id))
    }

    private var uid: String { auth.uid ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            listingHeader
            Divider()
            transcript
            sendFailureBanner
            Divider()
            composer
        }
        .navigationTitle(conversation.otherPartyName(for: uid))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        confirmBlock = true
                    } label: {
                        Label("Block \(conversation.otherPartyName(for: uid))", systemImage: "hand.raised.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Block \(conversation.otherPartyName(for: uid))?",
            isPresented: $confirmBlock,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                Task {
                    let other = conversation.buyerId == uid ? conversation.sellerId : conversation.buyerId
                    do {
                        try await blocks.block(
                            userId: other,
                            displayName: conversation.otherPartyName(for: uid)
                        )
                        dismiss()
                    } catch {
                        // Staying put on failure is the point: leaving would
                        // imply the block took effect when it did not.
                        blockError = "Couldn't block this person. Please try again."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This conversation will disappear from your inbox and neither of you will be able to message the other. You can undo this under Account → Blocked users.")
        }
        .onAppear {
            store.startIfNeeded()
            markRead()
        }
        .confirmationDialog(
            "Delete this message?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let message = pendingDeletion {
                    Task { await store.delete(message) }
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This removes it for both of you.")
        }
    }

    private var listingHeader: some View {
        HStack(spacing: 10) {
            ListingPhotoBox(url: conversation.photoURL, cornerRadius: 6)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(conversation.listingTitle)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                Text("Listing")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if store.isLoading {
                        ProgressView().padding(.top, 24)
                    } else if store.messages.isEmpty {
                        Text("Say hello — ask if it's still available.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                    }

                    ForEach(store.messages) { message in
                        MessageBubble(
                            message: message,
                            isMine: message.senderId == uid,
                            onDelete: message.senderId == uid
                                ? { pendingDeletion = message }
                                : nil
                        )
                        .id(message.id)
                    }
                }
                .padding(16)
                .readableWidth()
            }
            .onChange(of: store.messages.count) { _, _ in
                guard let last = store.messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                markRead()
            }
        }
    }

    @ViewBuilder
    private var sendFailureBanner: some View {
        if let message = blockError ?? store.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                Text(message)
                Spacer(minLength: 8)
                Button("Dismiss") {
                    blockError = nil
                    store.errorMessage = nil
                }
                .font(.caption.weight(.medium))
            }
            .font(.footnote)
            .foregroundStyle(.red)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: Capsule())

            Button {
                let text = draft
                draft = ""
                Task {
                    // Cleared optimistically so it feels immediate, then put
                    // straight back if it didn't land — losing what someone
                    // typed is worse than a moment of flicker.
                    if await store.send(text: text, senderId: uid) == false {
                        draft = text
                    }
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Theme.brand : Color.gray.opacity(0.5))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .readableWidth()
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !uid.isEmpty
    }

    private func markRead() {
        guard !uid.isEmpty else { return }
        Task {
            try? await ChatService.markRead(
                conversationId: conversation.id,
                uid: uid,
                buyerId: conversation.buyerId
            )
        }
    }
}

private struct MessageBubble: View {
    let message: Message
    let isMine: Bool
    /// Only supplied for your own messages — firestore.rules won't let you
    /// delete the other participant's.
    var onDelete: (() -> Void)?

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                SelectableText(
                    text: message.text,
                    color: isMine ? .white : .label,
                    destructiveAction: onDelete.map { (title: "Delete Message", perform: $0) }
                )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isMine ? Theme.brand : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )

                Text(Format.relativeTime(message.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !isMine { Spacer(minLength: 40) }
        }
    }
}
