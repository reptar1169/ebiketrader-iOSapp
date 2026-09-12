//
//  BlockedUsersView.swift
//  ebiketrader
//

import SwiftUI

/// Manage who you have blocked. Apple's guideline 1.2 wants blocking to exist
/// for user-generated content; it also has to be reversible, which is what
/// this screen is for.
struct BlockedUsersView: View {
    @EnvironmentObject private var blocks: BlockStore
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if blocks.blocked.isEmpty {
                ContentUnavailableView {
                    Label("Nobody blocked", systemImage: "hand.raised.slash")
                } description: {
                    Text("You can block someone from their listing or from a conversation.")
                }
            } else {
                List {
                    ForEach(blocks.blocked) { user in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.subheadline.weight(.medium))
                                if let blockedAt = user.createdAt,
                                   !Format.relativeTime(blockedAt).isEmpty {
                                    Text("Blocked \(Format.relativeTime(blockedAt))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Unblock") {
                                Task {
                                    do {
                                        try await blocks.unblock(userId: user.id)
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            }
                            .font(.footnote.weight(.medium))
                            .buttonStyle(.borderless)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Blocked users")
        .navigationBarTitleDisplayMode(.inline)
    }
}
