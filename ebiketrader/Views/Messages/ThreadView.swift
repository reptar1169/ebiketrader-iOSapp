//
//  ThreadView.swift
//  ebiketrader
//

import SwiftUI

struct ThreadView: View {
    let conversation: ConversationSummary

    @EnvironmentObject private var auth: AuthStore
    @StateObject private var store: ThreadStore
    @State private var draft = ""
    @State private var pendingDeletion: Message?

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
            Divider()
            composer
        }
        .navigationTitle(conversation.otherPartyName(for: uid))
        .navigationBarTitleDisplayMode(.inline)
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
            Text("This removes it for both of you. You can only delete your own messages.")
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
                        MessageBubble(message: message, isMine: message.senderId == uid)
                            .id(message.id)
                            .onLongPressGesture {
                                guard message.senderId == uid else { return }
                                pendingDeletion = message
                            }
                    }
                }
                .padding(16)
            }
            .onChange(of: store.messages.count) { _, _ in
                guard let last = store.messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                markRead()
            }
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
                Task { await store.send(text: text, senderId: uid) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Theme.brand : Color.gray.opacity(0.5))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !uid.isEmpty
    }

    private func markRead() {
        guard !uid.isEmpty else { return }
        Task {
            try? await Messaging.markRead(
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

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isMine ? Theme.brand : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .foregroundStyle(isMine ? .white : .primary)

                Text(Format.relativeTime(message.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !isMine { Spacer(minLength: 40) }
        }
    }
}
